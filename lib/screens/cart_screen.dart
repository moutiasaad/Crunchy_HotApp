import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../controllers/cart_controller.dart';
import '../models/models.dart';
import '../services/app_config_service.dart';
import '../services/catalog_service.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import '../utils/ch_routes.dart';
import '../widgets/ch_sign_in_prompt.dart';
import '../widgets/widgets.dart';
import 'app_shell.dart';
import 'branches_screen.dart';
import 'checkout_screen.dart';
import 'detail_screen.dart';
import 'login_screen.dart';

/// Screen 10 — Cart (السلة). Tab 3 of 5.
///
/// Review + adjust the order, pick delivery vs pickup, see the real total.
/// The summary is **not** pinned — it scrolls with the list (spec §2).
///
/// On tab-activate (i.e. every time the user switches into this tab), it
/// refreshes the live delivery fee via [AppConfigService.load] and re-fetches
/// each cart line's product via [CartController.refreshPrices] — so admin
/// price edits show up before the customer commits at Checkout.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  /// Below this the checkout CTA is disabled and a note appears above it.
  static const int _minOrderSyp = 25000;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  ChangeNotifier? _activate;
  ChangeNotifier? _retap;

  @override
  void initState() {
    super.initState();
    // First-mount refresh — if the app lands directly on Cart (initialTab: 2)
    // or opens straight into it, TabActivate never fires, so we prime the
    // fetch here too.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshFromApi());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Switch INTO Cart from another tab.
    final activate = TabActivate.of(context);
    if (activate != _activate) {
      _activate?.removeListener(_refreshFromApi);
      _activate = activate;
      _activate?.addListener(_refreshFromApi);
    }
    // Re-tap the Cart tab while already on it. Fires refresh too so the user
    // has a simple "pull for latest" muscle memory via the nav bar.
    final retap = TabRetap.of(context);
    if (retap != _retap) {
      _retap?.removeListener(_refreshFromApi);
      _retap = retap;
      _retap?.addListener(_refreshFromApi);
    }
  }

  @override
  void dispose() {
    _activate?.removeListener(_refreshFromApi);
    _retap?.removeListener(_refreshFromApi);
    super.dispose();
  }

  /// Pull the two things that drift silently from the server:
  ///   1. `business.delivery_fee_syp` via `/api/v1/config` (60s cached).
  ///   2. per-line product prices via `/products/{slug}` for each item.
  /// Both call chains publish through `notifyListeners()` on success, so the
  /// totals card + CTA reflow without any local `setState`.
  void _refreshFromApi() {
    if (!mounted) return;
    if (kDebugMode) debugPrint('[Cart] refreshFromApi — pulling /config + /products/{slug}×N');
    final config  = context.read<AppConfigService>();
    final catalog = context.read<CatalogService>();
    final cart    = context.read<CartController>();
    unawaited(config.load());
    unawaited(cart.refreshPrices(catalog));
  }

  @override
  Widget build(BuildContext context) {
    final cart       = context.watch<CartController>();
    final totals     = cart.totals;
    final belowMin   = !cart.isEmpty && totals.subtotal < CartScreen._minOrderSyp;
    final canCheckout = !cart.isEmpty && !belowMin;
    final topInset   = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Scaffold(
          backgroundColor: CH.cream,
          body: ListView(
            padding: EdgeInsets.only(top: topInset + 14, bottom: 40),
            children: [
              // ────── Title ──────
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
                child: Text(
                  'سلة الطلبات',
                  style: GoogleFonts.changa(
                    fontSize: 27, fontWeight: FontWeight.w800, color: CH.ink),
                ),
              ),

              // ────── Mode toggle (always visible, even when empty) ──────
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                child: _ModeSegmented(
                  mode:         cart.mode,
                  branchLabel:  cart.branch?.shortNameAr,
                  onDelivery:   () => context.read<CartController>().setMode(OrderMode.delivery),
                  onPickup:     () => _pickupTapped(context),
                ),
              ),
              const SizedBox(height: 14),

              // ────── Body ──────
              if (cart.isEmpty)
                _CartEmpty(onBrowse: () => AppShell.switchTo(context, 1))
              else ...[
                for (final line in cart.lines)
                  Padding(
                    key: ValueKey('wrap-${line.id}'),
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                    child: Dismissible(
                      key: ValueKey(line.id),
                      direction: DismissDirection.endToStart,
                      background: const _DeletePanel(),
                      onDismissed: (_) => _removeWithUndo(context, line),
                      child: _CartLineRow(
                        line: line,
                        onTap: () => _openDetail(context, line),
                        onInc: () => context.read<CartController>().updateQuantity(
                              line.id, (line.quantity + 1).clamp(1, 20)),
                        onDec: () {
                          if (line.quantity == 1) {
                            _removeWithUndo(context, line);
                          } else {
                            context.read<CartController>()
                                .updateQuantity(line.id, line.quantity - 1);
                          }
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                  child: _DashedAddMoreButton(
                    onTap: () => AppShell.switchTo(context, 1),
                  ),
                ),
                _CartSummary(
                  subtotal:      totals.subtotal,
                  fee:           totals.deliveryFee,
                  total:         totals.total,
                  mode:          cart.mode,
                  belowMinimum:  belowMin,
                  minOrderSyp:   CartScreen._minOrderSyp,
                  enabled:       canCheckout,
                  onCheckout:    () => _checkout(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────── Actions ───────────────────

  Future<void> _removeWithUndo(BuildContext context, CartLine line) async {
    final ctrl      = context.read<CartController>();
    final messenger = ScaffoldMessenger.of(context);

    ctrl.remove(line.id);
    HapticFeedback.lightImpact();

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('تم حذف ${line.product.nameAr}',
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
      backgroundColor: CH.char,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'تراجع',
        textColor: CH.hot,
        onPressed: () => ctrl.add(
          line.product,
          quantity: line.quantity,
          spice:    line.spice,
          addons:   line.addons,
          note:     line.note,
        ),
      ),
    ));
  }

  void _openDetail(BuildContext context, CartLine line) {
    Navigator.of(context).push(
      ChRoutes.slideUpFade(
        (_) => DetailScreen(product: line.product, editLineId: line.id),
      ),
    );
  }

  /// Pickup toggle handler (spec §3):
  ///   - always push Branches so the user can change branch;
  ///   - on cancel revert to Delivery only if no branch was ever picked;
  ///   - on select, [BranchesScreen] itself calls `setPickupBranch()`.
  Future<void> _pickupTapped(BuildContext context) async {
    final ctrl        = context.read<CartController>();
    final hadBranch   = ctrl.branch != null;

    final picked = await Navigator.of(context).push<Branch>(
      ChRoutes.slideUpFade((_) => const BranchesScreen()),
    );

    if (picked == null && !hadBranch) {
      // User backed out and no branch is stored → keep Delivery.
      ctrl.setMode(OrderMode.delivery);
    }
  }

  Future<void> _checkout(BuildContext context) async {
    // Spec §1: "Guests are sent to Login first and returned here with the
    // cart intact." Cart persists on CartController so it survives the gate.
    final auth = context.read<AuthController>();
    if (!auth.isSignedIn) {
      final wants = await showSignInPromptSheet(
        context,
        title: 'سجّل دخول لإتمام الطلب',
        body:  'حسابك بيحفظ طلباتك ونقاطك وعناوينك في مكان واحد.',
      );
      if (!wants || !context.mounted) return;

      final signed = await Navigator.of(context).push<bool>(
        ChRoutes.slideUpFade(
          (_) => const LoginScreen(returnOnSuccess: true),
          fullscreenDialog: true,
        ),
      );
      if (signed != true || !context.mounted) return;
    }

    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => const CheckoutScreen()),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Mode segmented — delivery vs pickup
// ══════════════════════════════════════════════════════════════════
class _ModeSegmented extends StatelessWidget {
  final OrderMode mode;
  final String?   branchLabel;   // shown on the pickup button once a branch is set
  final VoidCallback onDelivery;
  final VoidCallback onPickup;

  const _ModeSegmented({
    required this.mode,
    required this.branchLabel,
    required this.onDelivery,
    required this.onPickup,
  });

  static String _truncate(String s, int max) =>
      s.characters.length <= max ? s : '${s.characters.take(max).toString()}…';

  @override
  Widget build(BuildContext context) {
    final pickupLabel = branchLabel == null ? 'استلام' : _truncate(branchLabel!, 14);
    return Row(
      children: [
        Expanded(child: _ModeButton(
          label:  'توصيل',
          emoji:  '🛵',
          active: mode == OrderMode.delivery,
          onTap:  onDelivery,
        )),
        const SizedBox(width: 8),
        Expanded(child: _ModeButton(
          label:  pickupLabel,
          emoji:  '🏬',
          active: mode == OrderMode.pickup,
          onTap:  onPickup,
        )),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final String emoji;
  final bool   active;
  final VoidCallback onTap;
  const _ModeButton({
    required this.label, required this.emoji,
    required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      inMutuallyExclusiveGroup: true,
      label: label,
      child: Material(
        color: active ? CH.char : Colors.white,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: active ? null : Border.all(color: CH.line, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : CH.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Cart line row — image · info · stepper
// ══════════════════════════════════════════════════════════════════
class _CartLineRow extends StatelessWidget {
  final CartLine line;
  final VoidCallback onTap;
  final VoidCallback onInc;
  final VoidCallback onDec;

  const _CartLineRow({
    required this.line, required this.onTap,
    required this.onInc, required this.onDec,
  });

  String _optionsNote() {
    final parts = <String>[
      _spiceLabel(line.spice),
      ...line.addons.map((a) => a.nameAr),
    ];
    return parts.join(' · ');
  }

  static String _spiceLabel(Spice s) => switch (s) {
        Spice.mild     => 'عادي',
        Spice.hot      => 'حار',
        Spice.extraHot => 'حار جداً',
      };

  @override
  Widget build(BuildContext context) {
    final semanticsLabel =
        '${line.product.nameAr}, ${_optionsNote()}, ${line.quantity} × ${ChMoney.format(line.unitPrice)}';

    return Semantics(
      label: semanticsLabel,
      button: true,
      onTapHint: 'تعديل ${line.product.nameAr}',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Thumbnail
                _LineThumb(product: line.product),
                const SizedBox(width: 12),

                // Info column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        line.product.nameAr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.changa(
                          fontSize: 15, fontWeight: FontWeight.w800, color: CH.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _optionsNote(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 11, fontWeight: FontWeight.w600, color: CH.muted),
                      ),
                      const SizedBox(height: 3),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          ChMoney.format(line.lineTotal),
                          style: GoogleFonts.changa(
                            fontSize: 15, fontWeight: FontWeight.w800, color: CH.hot),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Stepper (always LTR internally per spec §11)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: _LineStepper(qty: line.quantity, onDec: onDec, onInc: onInc),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LineThumb extends StatelessWidget {
  final Product product;
  const _LineThumb({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62, height: 62,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CH.cream2,
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: (product.imageUrl == null || product.imageUrl!.isEmpty)
          ? Text(product.emoji, style: const TextStyle(fontSize: 36))
          : Image.network(
              product.imageUrl!,
              fit: BoxFit.cover,
              width:  62, height: 62,
              errorBuilder: (_, __, ___) =>
                  Text(product.emoji, style: const TextStyle(fontSize: 36)),
            ),
    );
  }
}

class _LineStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  const _LineStepper({required this.qty, required this.onDec, required this.onInc});

  @override
  Widget build(BuildContext context) {
    final canPlus = qty < 20;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: CH.line, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepGlyph(glyph: '−', enabled: true,   onTap: onDec, label: 'إنقاص'),
          const SizedBox(width: 12),
          SizedBox(
            width: 18,
            child: Semantics(
              liveRegion: true,
              child: Text('$qty',
                textAlign: TextAlign.center,
                style: GoogleFonts.changa(
                  fontSize: 15, fontWeight: FontWeight.w800, color: CH.ink)),
            ),
          ),
          const SizedBox(width: 12),
          _StepGlyph(glyph: '+', enabled: canPlus, onTap: onInc, label: 'زيادة'),
        ],
      ),
    );
  }
}

class _StepGlyph extends StatelessWidget {
  final String glyph;
  final bool enabled;
  final VoidCallback onTap;
  final String label;
  const _StepGlyph({
    required this.glyph, required this.enabled,
    required this.onTap, required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, label: label, enabled: enabled,
      child: SizedBox(
        width: 26, height: 26,
        child: InkResponse(
          onTap: enabled ? onTap : null,
          radius: 18,
          child: Center(
            child: Text(
              glyph,
              style: GoogleFonts.changa(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: enabled ? CH.hot : CH.inactive),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Delete panel — shown behind the row on end→start swipe
// ══════════════════════════════════════════════════════════════════
class _DeletePanel extends StatelessWidget {
  const _DeletePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: CH.red,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text('🗑', style: TextStyle(fontSize: 24, color: Colors.white)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  "أضف أصناف أخرى" — dashed rounded rectangle button
// ══════════════════════════════════════════════════════════════════
class _DashedAddMoreButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DashedAddMoreButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, label: 'أضف أصناف أخرى',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          painter: _DashedRRectPainter(
            color: CH.line,
            radius: 14,
            strokeWidth: 1.5,
            dashLength: 6,
            gapLength: 4,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '+  أضف أصناف أخرى',
                  style: GoogleFonts.cairo(
                    fontSize: 14, fontWeight: FontWeight.w800, color: CH.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Summary block + CTA
// ══════════════════════════════════════════════════════════════════
class _CartSummary extends StatelessWidget {
  final int subtotal;
  final int fee;
  final int total;
  final OrderMode mode;
  final bool belowMinimum;
  final int minOrderSyp;
  final bool enabled;
  final VoidCallback onCheckout;

  const _CartSummary({
    required this.subtotal, required this.fee, required this.total,
    required this.mode, required this.belowMinimum, required this.minOrderSyp,
    required this.enabled, required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final feeLabel = mode == OrderMode.delivery ? 'رسوم التوصيل' : 'الاستلام من الفرع';
    final feeValue = fee == 0 ? 'مجاناً' : ChMoney.format(fee);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow(label: 'المجموع الفرعي', value: ChMoney.format(subtotal)),
          const SizedBox(height: 8),
          _SummaryRow(
            label: feeLabel,
            value: feeValue,
            valueIsFreeTag: fee == 0,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 12),
            child: _DashedHLine(),
          ),
          _TotalRow(total: total),

          if (belowMinimum) ...[
            const SizedBox(height: 10),
            Text(
              'الحد الأدنى للطلب ${ChMoney.format(minOrderSyp)}',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 12, fontWeight: FontWeight.w700, color: CH.red),
            ),
          ],

          const SizedBox(height: 14),
          _CheckoutCta(enabled: enabled, onTap: onCheckout),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool valueIsFreeTag;
  const _SummaryRow({
    required this.label, required this.value, this.valueIsFreeTag = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = GoogleFonts.cairo(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: valueIsFreeTag ? CH.green : const Color(0xFF6D5D51),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
          style: GoogleFonts.cairo(
            fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF6D5D51))),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: Directionality(
            textDirection: TextDirection.ltr,
            key: ValueKey('$label-$value'),
            child: Text(value, style: valueStyle),
          ),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  final int total;
  const _TotalRow({required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('الإجمالي',
          style: GoogleFonts.changa(
            fontSize: 19, fontWeight: FontWeight.w800, color: CH.ink)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: Directionality(
            textDirection: TextDirection.ltr,
            key: ValueKey(total),
            child: Text(
              ChMoney.format(total),
              style: GoogleFonts.changa(
                fontSize: 19, fontWeight: FontWeight.w800, color: CH.hot),
            ),
          ),
        ),
      ],
    );
  }
}

class _CheckoutCta extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _CheckoutCta({required this.enabled, required this.onTap});

  @override
  State<_CheckoutCta> createState() => _CheckoutCtaState();
}

class _CheckoutCtaState extends State<_CheckoutCta> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, enabled: widget.enabled,
      hint: widget.enabled ? null : 'المبلغ أقل من الحد الأدنى',
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: widget.enabled ? ChShadows.primaryButton : null,
          ),
          child: Material(
            color: !widget.enabled ? CH.line : (_pressed ? CH.hotDeep : CH.hot),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: widget.enabled ? widget.onTap : null,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Center(
                  child: Text(
                    'إتمام الطلب',
                    style: GoogleFonts.changa(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: widget.enabled ? Colors.white : CH.inactive),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Empty state — 🛒 + copy + Menu CTA
// ══════════════════════════════════════════════════════════════════
class _CartEmpty extends StatelessWidget {
  final VoidCallback onBrowse;
  const _CartEmpty({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    // Anchor the empty state ~35% down the remaining space.
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 60, 40, 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🛒', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 14),
          Text(
            'سلتك فارغة',
            textAlign: TextAlign.center,
            style: GoogleFonts.changa(
              fontSize: 18, fontWeight: FontWeight.w800, color: CH.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'أضف أصنافك من المنيو لتظهر هنا.',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(fontSize: 14, color: CH.muted, height: 1.6),
          ),
          const SizedBox(height: 18),
          ChDarkButton(
            label: 'تصفّح المنيو',
            onPressed: onBrowse,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Dashed border painters (round rect + horizontal line)
// ══════════════════════════════════════════════════════════════════
class _DashedRRectPainter extends CustomPainter {
  final Color  color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _DashedRRectPainter({
    required this.color, required this.radius,
    required this.strokeWidth, required this.dashLength, required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      final len = metric.length;
      while (distance < len) {
        final end = (distance + dashLength).clamp(0.0, len);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dashLength != dashLength ||
      old.gapLength != gapLength;
}

class _DashedHLine extends StatelessWidget {
  const _DashedHLine();
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1,
        child: CustomPaint(
          painter: _DashedHLinePainter(
            color: const Color(0xFFE6D6C6),
            dashLength: 5,
            gapLength: 4,
            strokeWidth: 1,
          ),
          child: const SizedBox.expand(),
        ),
      );
}

class _DashedHLinePainter extends CustomPainter {
  final Color color;
  final double dashLength;
  final double gapLength;
  final double strokeWidth;

  _DashedHLinePainter({
    required this.color, required this.dashLength,
    required this.gapLength, required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dashLength).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(_DashedHLinePainter old) =>
      old.color != color ||
      old.dashLength != dashLength ||
      old.gapLength != gapLength ||
      old.strokeWidth != strokeWidth;
}
