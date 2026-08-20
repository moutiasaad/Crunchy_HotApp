import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/cart_controller.dart';
import '../controllers/favourites_controller.dart';
import '../models/models.dart';
import '../services/catalog_service.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import 'app_shell.dart';

/// Screen 08 — Item Detail (تفاصيل الصنف).
///
/// Configure one product (spice · add-ons · qty) and add it to the cart.
/// The total in the CTA is always live — recomputed on every change.
/// See `docs/ITEM_DETAIL_SCREEN.md` for the full spec.
class DetailScreen extends StatefulWidget {
  final Product product;

  /// If set, we're editing an existing cart line — the CTA label switches
  /// to "حدّث الطلب" and (when Cart lands) the picked options preload.
  final String? editLineId;

  /// When the screen is opened from an active offer, the unit price is the
  /// offer price and the add-to-cart call ships `offer_id` to the server.
  final Offer? fromOffer;

  const DetailScreen({
    super.key,
    required this.product,
    this.editLineId,
    this.fromOffer,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  int _qty = 1;

  /// Live product state — starts as whatever the list handed us so the sheet
  /// paints instantly, then swaps to the fresh `/products/{slug}` payload
  /// when the API call returns. That's how newly-published admin edits
  /// (price / options / images) reach the user without a full menu reload.
  late Product _product = widget.product;

  /// Per-group picks for products that have configured option groups.
  /// Keyed by `OptionGroup.id`; value = the set of selected `OptionValue.id`s.
  /// Initialised in `initState` from each group's default/first option so the
  /// live total isn't zero on first frame.
  final Map<int, Set<int>> _pickedOptions = {};

  Product get _p => _product;

  bool get _hasConfiguredOptions => _p.optionGroups.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _seedPickedOptions();
    // Prime the favourites list so the heart shows the correct state on
    // first paint (before the user pulls to refresh Menu / opens Favourites).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FavouritesController>().ensureLoaded();
      _refreshFromApi();
    });
  }

  Future<void> _refreshFromApi() async {
    final slug = widget.product.slug;
    if (slug.isEmpty) return;
    try {
      final fresh = await context.read<CatalogService>().getBySlug(slug);
      if (!mounted) return;
      setState(() {
        _product = fresh;
        _pickedOptions.clear();
        _seedPickedOptions();
      });
    } catch (_) {
      // Silent — the passed-in product is still visible; user's flow isn't
      // blocked. A retry happens naturally on the next open.
    }
  }

  void _seedPickedOptions() {
    for (final g in _p.optionGroups) {
      final defaults = g.options
          .where((o) => o.isDefault && o.isAvailable)
          .map((o) => o.id)
          .toSet();
      if (defaults.isNotEmpty) {
        _pickedOptions[g.id] = defaults;
        continue;
      }
      // Required single-select with no explicit default → seed with the first
      // available option so the user starts in a valid state.
      if (g.isSingleSelect && g.isRequired) {
        final first = g.options.firstWhere(
          (o) => o.isAvailable,
          orElse: () => g.options.isEmpty
              ? const OptionValue(id: 0, nameAr: '', nameEn: '', priceDelta: 0)
              : g.options.first,
        );
        if (first.id != 0) {
          _pickedOptions[g.id] = {first.id};
        }
      } else {
        _pickedOptions[g.id] = <int>{};
      }
    }
  }

  void _pickSingle(OptionGroup group, OptionValue value) {
    setState(() {
      _pickedOptions[group.id] = {value.id};
    });
  }

  void _toggleMulti(OptionGroup group, OptionValue value) {
    final set = _pickedOptions.putIfAbsent(group.id, () => <int>{});
    setState(() {
      if (set.contains(value.id)) {
        set.remove(value.id);
      } else if (set.length < group.maxSelect) {
        set.add(value.id);
      } else {
        // At the cap — replace the oldest pick so the tap still registers.
        // For a limit-2 group, tapping a third option should feel deliberate
        // rather than silently doing nothing.
        set
          ..remove(set.first)
          ..add(value.id);
      }
    });
  }

  int get _optionsDelta {
    if (!_hasConfiguredOptions) return 0;
    int sum = 0;
    for (final g in _p.optionGroups) {
      final picks = _pickedOptions[g.id] ?? const {};
      for (final o in g.options) {
        if (picks.contains(o.id)) sum += o.priceDelta;
      }
    }
    return sum;
  }

  /// The picked options materialised as [Addon]s so they flow into the cart
  /// through the existing `CartController.add(..., addons:)` API without a
  /// wider refactor. Addon.id is stringified from the server option id, which
  /// is what the cart's identity check keys on.
  List<Addon> get _pickedOptionsAsAddons {
    if (!_hasConfiguredOptions) return const [];
    final out = <Addon>[];
    for (final g in _p.optionGroups) {
      final picks = _pickedOptions[g.id] ?? const {};
      for (final o in g.options) {
        if (picks.contains(o.id)) {
          out.add(Addon(
            id:     o.id.toString(),
            nameAr: o.nameAr,
            nameEn: o.nameEn,
            price:  o.priceDelta,
          ));
        }
      }
    }
    return out;
  }

  Future<void> _toggleFavourite() async {
    HapticFeedback.selectionClick();
    final result = await context.read<FavouritesController>().toggle(_p);
    if (!mounted) return;
    switch (result) {
      case FavouriteToggleResult.full:
        _favToast('وصلت الحد الأقصى للمفضلة');
      case FavouriteToggleResult.guest:
        _favToast('سجّل دخولك لحفظ المفضلة');
      case FavouriteToggleResult.error:
        _favToast('ما قدرنا نحفظ الصنف — جرّب مرة تانية');
      case FavouriteToggleResult.added:
      case FavouriteToggleResult.removed:
        // The glass button re-renders with the new glyph — no toast needed.
        break;
    }
  }

  void _favToast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 26),
        duration: const Duration(milliseconds: 1800),
      ));
  }

  /// Base unit price before options + qty. Comes from the offer when the
  /// screen was opened via the offer bridge, otherwise the fresh product base.
  int get _unitBase => widget.fromOffer?.price ?? _p.price;

  int get _total => (_unitBase + _optionsDelta) * _qty;

  /// Any required group with fewer picks than its `minSelect` blocks the CTA
  /// and returns the first-encountered reason for the snackbar.
  String? _missingRequiredReason() {
    if (!_hasConfiguredOptions) return null;
    for (final g in _p.optionGroups) {
      if (!g.isRequired) continue;
      // Skip a required group with no options — an admin misconfig; the user
      // has nothing to pick, so blocking add-to-cart would trap them. Backend
      // mirrors this guard in CartManager::assertOptionsValid.
      if (g.options.isEmpty) continue;
      final n = (_pickedOptions[g.id] ?? const {}).length;
      if (n < g.minSelect) return 'الرجاء اختيار: ${g.nameAr}';
    }
    return null;
  }

  Future<void> _onAdd() async {
    final blocker = _missingRequiredReason();
    if (blocker != null) {
      _favToast(blocker);
      return;
    }
    HapticFeedback.mediumImpact();
    context.read<CartController>().add(
          _p,
          quantity: _qty,
          addons:   _pickedOptionsAsAddons,
          offer:    widget.fromOffer,
        );

    // Keep the user on Detail so they can add another size / customisation
    // in one flow — most users add 2-3 things before opening the cart.
    // A char-tinted snackbar confirms the add and offers a one-tap shortcut
    // to the Cart tab for anyone ready to check out.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          _qty > 1 ? 'أُضيف ${_p.nameAr} × $_qty للسلة' : 'أُضيف ${_p.nameAr} للسلة',
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        // 90dp above the bottom edge so it clears the Detail sheet's fixed
        // CTA bar without floating high up the screen.
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        duration: const Duration(milliseconds: 2500),
        action: SnackBarAction(
          label: 'عرض السلة',
          textColor: CH.hot,
          onPressed: () {
            // Close Detail so back-from-Cart lands on the tab the user came
            // from, then jump the shell to the Cart tab.
            Navigator.of(context).maybePop();
            AppShell.switchTo(context, 2);
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final size     = MediaQuery.sizeOf(context);
    final heroH    = size.height >= 800 ? 300.0 : 280.0;
    final isFav    = context.watch<FavouritesController>().isFavourite(_p.id);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.4,
        child: Scaffold(
          backgroundColor: Colors.white,
          extendBodyBehindAppBar: true,
          body: Column(
            children: [
              // ────── 1) Hero image + glass buttons ──────
              _HeroImage(
                product: _p,
                height:  heroH,
                isFav:   isFav,
                isRtl:   isArabic,
                onBack:  () => Navigator.of(context).maybePop(),
                onFav:   _toggleFavourite,
              ),

              // ────── 2) Scrollable sheet (overlaps image by -26) ──────
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -26),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 46),
                      children: [
                        _HeaderRow(
                          product:      _p,
                          displayPrice: _unitBase,
                          strikePrice:  widget.fromOffer?.originalPrice,
                        ),
                        const SizedBox(height: 14),
                        _Description(text: _descriptionFor(_p)),
                        const SizedBox(height: 22),

                        // ── Server-driven option groups (renders nothing
                        //    when the admin hasn't configured any).
                        for (final group in _p.optionGroups.where((g) => g.options.isNotEmpty)) ...[
                          _GroupHead(
                            title:      group.nameAr,
                            hint:       group.isRequired ? 'مطلوب' : 'اختياري',
                            hintColor:  group.isRequired ? CH.hot : CH.muted,
                          ),
                          const SizedBox(height: 10),
                          if (group.isSingleSelect)
                            _RadioOptionsRow(
                              options:  group.options,
                              selected: (_pickedOptions[group.id]?.isEmpty ?? true)
                                  ? null
                                  : _pickedOptions[group.id]!.first,
                              onPick:   (v) => _pickSingle(group, v),
                            )
                          else
                            Column(
                              children: [
                                for (int i = 0; i < group.options.length; i++) ...[
                                  _OptionCheckboxRow(
                                    option:  group.options[i],
                                    checked: (_pickedOptions[group.id] ?? const {})
                                        .contains(group.options[i].id),
                                    onTap:   () => _toggleMulti(group, group.options[i]),
                                  ),
                                  if (i != group.options.length - 1)
                                    const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          const SizedBox(height: 24),
                        ],

                        _QuantityRow(
                          qty:   _qty,
                          onDec: () => setState(() => _qty = math.max(1, _qty - 1)),
                          onInc: () => setState(() => _qty = math.min(20, _qty + 1)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ────── 3) Bottom action bar ──────
              _BottomBar(
                label: widget.editLineId == null ? 'أضف للسلة' : 'حدّث الطلب',
                total: _total,
                onTap: _onAdd,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Prefer the (currently-not-in-API) long description, fall back to short.
  static String _descriptionFor(Product p) =>
      p.descriptionAr.isNotEmpty ? p.descriptionAr : p.nameAr;
}

// ═════════════════════════════════════════════════════════════════
//  Hero image + two glass buttons (back at END, heart at START).
//  Reverse of the usual pattern — matches the reference build and
//  keeps back under the thumb in RTL (spec §9).
// ═════════════════════════════════════════════════════════════════
class _HeroImage extends StatelessWidget {
  final Product product;
  final double  height;
  final bool    isFav;
  final bool    isRtl;
  final VoidCallback onBack;
  final VoidCallback onFav;

  const _HeroImage({
    required this.product, required this.height,
    required this.isFav,   required this.isRtl,
    required this.onBack,  required this.onFav,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: Hero(
              tag: 'product-${product.id}',
              child: _productImage(product),
            ),
          ),
          // Back at the leading edge (start), heart at the trailing edge
          // (end) — swapped from the earlier layout.
          PositionedDirectional(
            top: 58, start: 16,
            child: _GlassCircleButton(
              glyph: isRtl ? '→' : '←',
              label: 'رجوع',
              onTap: onBack,
            ),
          ),
          PositionedDirectional(
            top: 58, end: 16,
            child: _GlassCircleButton(
              glyph: isFav ? '❤️' : '🤍',
              label: isFav ? 'إزالة من المفضّلة' : 'أضف للمفضّلة',
              onTap: onFav,
            ),
          ),
        ],
      ),
    );
  }

  Widget _productImage(Product p) {
    Widget fallback() => Container(
          color: CH.cream2,
          alignment: Alignment.center,
          child: Text(p.emoji, style: const TextStyle(fontSize: 220)),
        );

    final url = p.imageUrl;
    if (url == null || url.isEmpty) return fallback();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder:   (_, __, ___)              => fallback(),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : fallback(),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  final String glyph;
  final String label;
  final VoidCallback onTap;
  const _GlassCircleButton({
    required this.glyph, required this.label, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, label: label,
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40, height: 40,
            child: Center(
              child: Text(
                glyph,
                style: GoogleFonts.cairo(
                  fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Header row — name + rating line (start), price (end)
// ═════════════════════════════════════════════════════════════════
class _HeaderRow extends StatelessWidget {
  final Product product;

  /// Shown big and hot on the trailing side. Equal to `product.price` for
  /// normal flows, or the offer price when opened via the offer bridge.
  final int displayPrice;

  /// When non-null, rendered above [displayPrice] with a strikethrough — the
  /// "was 32,000, now 25,000" pattern for offer lines.
  final int? strikePrice;

  const _HeaderRow({
    required this.product,
    required this.displayPrice,
    this.strikePrice,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.nameAr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.changa(
                  fontSize: 24, fontWeight: FontWeight.w800, color: CH.ink,
                  height: 1.25),
              ),
              const SizedBox(height: 5),
              Text(
                _ratingLine(product),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w600, color: CH.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (strikePrice != null && strikePrice! > displayPrice)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  ChMoney.format(strikePrice!),
                  style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w700, color: CH.muted,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: CH.muted,
                  ),
                ),
              ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                ChMoney.format(displayPrice),
                style: GoogleFonts.changa(
                  fontSize: 24, fontWeight: FontWeight.w800, color: CH.hot),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _ratingLine(Product p) {
    final rating = p.ratingAvg > 0
        ? '⭐ ${p.ratingAvg.toStringAsFixed(1)}'
        : '⭐ 4.8';
    return p.descriptionAr.isNotEmpty ? '$rating · ${p.descriptionAr}' : rating;
  }
}

// ═════════════════════════════════════════════════════════════════
//  Description block
// ═════════════════════════════════════════════════════════════════
class _Description extends StatelessWidget {
  final String text;
  const _Description({required this.text});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.cairo(
          fontSize: 14, height: 1.8, color: const Color(0xFF6D5D51)),
      );
}

class _Checkbox extends StatelessWidget {
  final bool checked;
  const _Checkbox({required this.checked});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 22, height: 22,
      decoration: BoxDecoration(
        color: checked ? CH.hot : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: checked ? CH.hot : const Color(0xFFDCCBBA),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: !checked
          ? null
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              builder: (_, v, __) => Transform.scale(
                scale: v,
                child: const Icon(Icons.check, color: Colors.white, size: 13),
              ),
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Server-driven groups — head + radio row + checkbox row
// ═════════════════════════════════════════════════════════════════
class _GroupHead extends StatelessWidget {
  final String title;
  final String hint;
  final Color  hintColor;
  const _GroupHead({
    required this.title, required this.hint, required this.hintColor,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(title,
              style: GoogleFonts.changa(
                fontSize: 16, fontWeight: FontWeight.w800, color: CH.ink)),
          ),
          Text(hint,
            style: GoogleFonts.cairo(
              fontSize: 12, fontWeight: FontWeight.w700, color: hintColor)),
        ],
      );
}

/// Single-select group — one row of equal-width buttons. Selected button
/// gets the `hot` fill; the rest are white with a 1.5 px `line` border.
/// Uses `Wrap` so >3 options flow onto a second line rather than overflow.
class _RadioOptionsRow extends StatelessWidget {
  final List<OptionValue>       options;
  final int?                    selected;
  final ValueChanged<OptionValue> onPick;

  const _RadioOptionsRow({
    required this.options, required this.selected, required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (options.length <= 3) {
      return Row(
        children: List.generate(options.length, (i) {
          final o      = options[i];
          final active = o.id == selected;
          return Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                end: i == options.length - 1 ? 0 : 8,
              ),
              child: _RadioButton(option: o, active: active, onTap: () => onPick(o)),
            ),
          );
        }),
      );
    }
    // >3 options: wrap into two rows.
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: [
        for (final o in options)
          _RadioButton(
            option: o, active: o.id == selected, onTap: () => onPick(o),
          ),
      ],
    );
  }
}

class _RadioButton extends StatelessWidget {
  final OptionValue option;
  final bool        active;
  final VoidCallback onTap;
  const _RadioButton({
    required this.option, required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: active,
      button: true,
      label: option.nameAr,
      child: Material(
        color: active ? CH.hot : Colors.white,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: option.isAvailable ? onTap : null,
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: active ? null : Border.all(color: CH.line, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(option.nameAr,
                  style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: active ? Colors.white : CH.ink)),
                if (option.priceDelta > 0) ...[
                  const SizedBox(width: 6),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('+ ${ChMoney.format(option.priceDelta)}',
                      style: GoogleFonts.cairo(
                        fontSize: 11, fontWeight: FontWeight.w800,
                        color: active ? Colors.white : CH.hot)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionCheckboxRow extends StatelessWidget {
  final OptionValue option;
  final bool        checked;
  final VoidCallback onTap;
  const _OptionCheckboxRow({
    required this.option, required this.checked, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      button: true,
      label: '${option.nameAr}, ${checked ? "محدّد" : "غير محدّد"}',
      child: Opacity(
        opacity: option.isAvailable ? 1.0 : 0.5,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: option.isAvailable ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: checked ? CH.hot : CH.line,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  _Checkbox(checked: checked),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(option.nameAr,
                      style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.w700, color: CH.ink)),
                  ),
                  if (option.priceDelta > 0)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text('+ ${ChMoney.format(option.priceDelta)}',
                        style: GoogleFonts.cairo(
                          fontSize: 13, fontWeight: FontWeight.w800, color: CH.hot)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Quantity — label + stepper
// ═════════════════════════════════════════════════════════════════
class _QuantityRow extends StatelessWidget {
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  const _QuantityRow({required this.qty, required this.onDec, required this.onInc});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'الكمية',
          style: GoogleFonts.changa(
            fontSize: 16, fontWeight: FontWeight.w800, color: CH.ink),
        ),
        _Stepper(qty: qty, onDec: onDec, onInc: onInc),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  const _Stepper({required this.qty, required this.onDec, required this.onInc});

  @override
  Widget build(BuildContext context) {
    final canMinus = qty > 1;
    final canPlus  = qty < 20;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CH.line, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true, label: 'إنقاص الكمية',
            child: SizedBox(
              width: 26, height: 26,
              child: InkResponse(
                onTap: canMinus ? onDec : null,
                radius: 18,
                child: Center(
                  child: Text(
                    '−',
                    style: GoogleFonts.changa(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: canMinus ? CH.hot : CH.inactive,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Semantics(
            liveRegion: true,
            child: SizedBox(
              width: 20,
              child: Text(
                '$qty',
                textAlign: TextAlign.center,
                style: GoogleFonts.changa(
                  fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Semantics(
            button: true, label: 'زيادة الكمية',
            child: SizedBox(
              width: 26, height: 26,
              child: InkResponse(
                onTap: canPlus ? onInc : null,
                radius: 18,
                child: Center(
                  child: Text(
                    '+',
                    style: GoogleFonts.changa(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: canPlus ? CH.hot : CH.inactive,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Bottom action bar — fixed CTA with live total
// ═════════════════════════════════════════════════════════════════
class _BottomBar extends StatelessWidget {
  final String label;
  final int    total;
  final VoidCallback onTap;
  const _BottomBar({required this.label, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(
        top: 14,
        left: 20, right: 20,
        bottom: 20 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: CH.navTopBorder, width: 1)),
      ),
      child: _CtaButton(label: label, total: total, onTap: onTap),
    );
  }
}

class _CtaButton extends StatefulWidget {
  final String label;
  final int    total;
  final VoidCallback onTap;
  const _CtaButton({required this.label, required this.total, required this.onTap});

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: _pressed ? 0.98 : 1.0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: ChShadows.primaryButton,
        ),
        child: Material(
          color: _pressed ? CH.hotDeep : CH.hot,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _pressed = v),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.label,
                    style: GoogleFonts.changa(
                      fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  Text(
                    '  ·  ',
                    style: GoogleFonts.changa(
                      fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                      child: Text(
                        ChMoney.format(widget.total),
                        key: ValueKey(widget.total),
                        style: GoogleFonts.changa(
                          fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
