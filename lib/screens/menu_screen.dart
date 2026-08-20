import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/cart_controller.dart';
import '../controllers/favourites_controller.dart';
import '../controllers/menu_controller.dart' as ch;
import '../models/models.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import '../utils/ch_routes.dart';
import '../widgets/widgets.dart';
import 'app_shell.dart';
import 'detail_screen.dart';
import 'favourites_screen.dart';
import 'search_screen.dart';

/// Screen 07 — Menu (المنيو).
///
/// Full catalogue, one category at a time. Entered from bottom-nav tab 1,
/// from Home category chips (with `initialCategory`), or from Search's
/// empty state. See `MENU_SCREEN.md` for the full spec.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.initialCategory});
  final String? initialCategory;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final ScrollController _scroll = ScrollController();

  /// Drives the sticky-rail bottom border fade — §4/§8.
  final ValueNotifier<bool> _railOverlaps = ValueNotifier<bool>(false);

  ChangeNotifier? _retap;
  ChangeNotifier? _activate;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ch.MenuController>().init(
            initialCategory: widget.initialCategory,
          );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Menu tab re-tap: reset to the default category and scroll to top.
    final retap = TabRetap.of(context);
    if (retap != _retap) {
      _retap?.removeListener(_handleMenuReTap);
      _retap = retap;
      _retap?.addListener(_handleMenuReTap);
    }
    // Tab-activate: refresh categories + current slug so admin edits appear.
    final activate = TabActivate.of(context);
    if (activate != _activate) {
      _activate?.removeListener(_refreshFromApi);
      _activate = activate;
      _activate?.addListener(_refreshFromApi);
    }
  }

  @override
  void dispose() {
    _retap?.removeListener(_handleMenuReTap);
    _activate?.removeListener(_refreshFromApi);
    _scroll.removeListener(_onScroll);
    _railOverlaps.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refreshFromApi() {
    if (!mounted) return;
    context.read<ch.MenuController>().refresh();
  }

  void _onScroll() {
    // Infinite scroll trigger — start loading the next page 400 dp before the
    // bottom so the user never sees a hard stop.
    final vm = context.read<ch.MenuController>();
    final pos = _scroll.position;
    if (pos.pixels + 400 >= pos.maxScrollExtent && vm.hasMore) {
      vm.loadMore();
    }
  }

  /// Spec §1: re-tapping the tab scrolls to top; if a non-default category
  /// is active it first resets to the default category.
  Future<void> _handleMenuReTap() async {
    final vm = context.read<ch.MenuController>();
    final defaultSlug =
        vm.categories.isNotEmpty ? vm.categories.first.slug : null;

    if (defaultSlug != null && vm.category != defaultSlug) {
      await vm.setCategory(defaultSlug);
    }
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  // ─────────────────────── Nav pushes ───────────────────────
  void _openDetail(Product p) {
    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => DetailScreen(product: p)),
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      ChRoutes.fade((_) => const SearchScreen()),
    );
  }

  void _openFavourites() {
    // Prime the list so the screen opens with data instead of a spinner.
    context.read<FavouritesController>().ensureLoaded();
    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => const FavouritesScreen()),
    );
  }

  Future<void> _toggleFavourite(Product product) async {
    final result = await context.read<FavouritesController>().toggle(product);
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
        // No toast on the Menu row heart — the fill animation is enough.
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
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(milliseconds: 1800),
      ));
  }

  // ─────────────────────── Cart / favourite actions ───────────────────────
  void _addToCart(Product p) {
    // Spec §6: items with required options must open detail. Product model
    // doesn't expose that flag yet — quick-adds go straight to the cart per
    // backend `CartManager::fillRequiredDefaults` (see memory).
    HapticFeedback.lightImpact();
    context.read<CartController>().add(p);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          'أُضيف ${p.nameAr} للسلة',
          style: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        duration: const Duration(milliseconds: 2200),
      ));
  }

  Future<void> _refresh() => context.read<ch.MenuController>().refresh();

  @override
  Widget build(BuildContext context) {
    final vm   = context.watch<ch.MenuController>();
    final fav  = context.watch<FavouritesController>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: CH.cream,
        body: RefreshIndicator(
          color: CH.hot,
          backgroundColor: Colors.white,
          onRefresh: _refresh,
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              // Spec §4/§8: the rail's bottom border fades in once content
              // starts scrolling under it.
              _railOverlaps.value = _scroll.hasClients && _scroll.offset > 4;
              return false;
            },
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ───── 1) Title row (§3) ─────
                SliverPadding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 54 + 8, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'المنيو',
                          style: GoogleFonts.changa(
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                            color: CH.ink,
                          ),
                        ),
                        Row(children: [
                          _IconBoxButton(
                            glyph: '🔍',
                            semanticLabel: 'ابحث في المنيو',
                            onTap: _openSearch,
                          ),
                          const SizedBox(width: 8),
                          _IconBoxButton(
                            glyph: '🤍',
                            semanticLabel: 'المفضلة',
                            dot: fav.hasFavourites,
                            onTap: _openFavourites,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),

                // ───── 2) Sticky category rail (§4) ─────
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _CategoryRailHeader(
                    categories:  vm.categories,
                    selected:    vm.category,
                    onPick:      (slug) async {
                      HapticFeedback.selectionClick();
                      await context.read<ch.MenuController>().setCategory(slug);
                      if (!mounted) return;
                      if (_scroll.hasClients) {
                        _scroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    borderVisible: _railOverlaps,
                  ),
                ),

                // ───── Offline / Closed strips (§7) ─────
                if (vm.offline)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                      child: _NoticeCard(
                        color: CH.cream2,
                        text: 'ما في اتصال — بنعرض آخر منيو محفوظ',
                        textColor: CH.ink,
                      ),
                    ),
                  ),
                if (vm.closed)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                      child: _NoticeCard(
                        color: CH.char,
                        text: 'المطعم مقفل · يفتح 12:00 ظهراً',
                        textColor: Colors.white,
                      ),
                    ),
                  ),

                // ───── 3) Content: skeleton / error / empty / list ─────
                _MenuBody(
                  vm: vm,
                  fav: fav,
                  onOpenDetail: _openDetail,
                  onAdd: _addToCart,
                  onFavourite: _toggleFavourite,
                  onRetry: () => context.read<ch.MenuController>().refresh(),
                  closed: vm.closed,
                ),

                // Bottom breathing room + loadMore sentinel.
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 26),
                  sliver: SliverToBoxAdapter(
                    child: vm.loadingMore
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: CH.hot),
                              ),
                            ),
                          )
                        : const SizedBox(height: 0),
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
//  Body sliver — dispatches to skeleton / error / empty / list.
//  Split out so the parent build stays readable.
// ══════════════════════════════════════════════════════════════════
class _MenuBody extends StatelessWidget {
  final ch.MenuController    vm;
  final FavouritesController fav;
  final void Function(Product p) onOpenDetail;
  final void Function(Product p) onAdd;
  final void Function(Product p) onFavourite;
  final VoidCallback onRetry;
  final bool closed;

  const _MenuBody({
    required this.vm,
    required this.fav,
    required this.onOpenDetail,
    required this.onAdd,
    required this.onFavourite,
    required this.onRetry,
    required this.closed,
  });

  @override
  Widget build(BuildContext context) {
    // Skeleton — §7.
    if (vm.loading && vm.items.isEmpty && vm.error == null) {
      return SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
        sliver: SliverList.separated(
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => const _ProductRowSkeleton(),
        ),
      );
    }

    // Error — §7.
    if (vm.error != null && vm.items.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _ErrorCard(msg: vm.error!, onRetry: onRetry),
        ),
      );
    }

    // Empty category — §7.
    if (vm.items.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _EmptyCategoryBlock(
            onSeeAll: () {
              // "See all items" → scroll back to the default (first) chip.
              final vm = context.read<ch.MenuController>();
              if (vm.categories.isNotEmpty) {
                vm.setCategory(vm.categories.first.slug);
              }
            },
          ),
        ),
      );
    }

    // Real list — §5.
    return SliverPadding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
      sliver: SliverList.separated(
        itemCount: vm.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final p = vm.items[i];
          return _ProductRow(
            product: p,
            favourite: fav.isFavourite(p.id),
            disabled: closed,
            onTap: () => onOpenDetail(p),
            onAdd: closed ? null : () => onAdd(p),
            onFavourite: () => onFavourite(p),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  §4 — Sticky category rail. minExtent == maxExtent == 62.
// ══════════════════════════════════════════════════════════════════
class _CategoryRailHeader extends SliverPersistentHeaderDelegate {
  final List<MenuCategory>       categories;
  final String?                  selected;
  final ValueChanged<String>     onPick;
  final ValueListenable<bool>    borderVisible;

  _CategoryRailHeader({
    required this.categories,
    required this.selected,
    required this.onPick,
    required this.borderVisible,
  });

  @override
  double get minExtent => 62;
  @override
  double get maxExtent => 62;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ValueListenableBuilder<bool>(
      valueListenable: borderVisible,
      builder: (_, visible, __) {
        return Container(
          height: 62,
          padding: const EdgeInsets.only(top: 6, bottom: 14),
          decoration: BoxDecoration(
            color: CH.cream,
            border: Border(
              bottom: BorderSide(
                color:
                    visible ? CH.line : CH.line.withValues(alpha: 0),
                width: 1,
              ),
            ),
          ),
          child: _CategoryRailContent(
            categories: categories,
            selected:   selected,
            onPick:     onPick,
          ),
        );
      },
    );
  }

  @override
  bool shouldRebuild(covariant _CategoryRailHeader oldDelegate) =>
      oldDelegate.categories != categories ||
      oldDelegate.selected   != selected;
}

/// Auto-scrolls to keep the selected chip visible when it's set
/// programmatically. Uses a stateful widget so the ScrollController survives
/// delegate rebuilds inside the sliver.
class _CategoryRailContent extends StatefulWidget {
  final List<MenuCategory>   categories;
  final String?              selected;
  final ValueChanged<String> onPick;

  const _CategoryRailContent({
    required this.categories,
    required this.selected,
    required this.onPick,
  });

  @override
  State<_CategoryRailContent> createState() => _CategoryRailContentState();
}

class _CategoryRailContentState extends State<_CategoryRailContent> {
  final ScrollController _rail = ScrollController();

  @override
  void didUpdateWidget(covariant _CategoryRailContent old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  void _scrollToSelected() {
    if (!_rail.hasClients) return;
    final idx = widget.categories.indexWhere((c) => c.slug == widget.selected);
    if (idx < 0) return;
    // Approximate chip width; the rail auto-fits so precision isn't critical.
    const chipStride = 96.0;
    final target = (idx * chipStride - 40).clamp(0.0, _rail.position.maxScrollExtent);
    _rail.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _rail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'الأقسام',
      child: ListView.separated(
        controller: _rail,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
        itemCount: widget.categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = widget.categories[i];
          final on = c.slug == widget.selected;
          return Semantics(
            selected: on,
            button: true,
            child: ChChip(
              label:    c.labelAr,
              emoji:    c.emoji,
              selected: on,
              onTap:    () => widget.onPick(c.slug),
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  §5 — Product row.
//  White radius 18, 80-sq image, name/desc/price/kcal, `+` and heart.
// ══════════════════════════════════════════════════════════════════
class _ProductRow extends StatelessWidget {
  final Product      product;
  final bool         favourite;
  /// True when the whole screen is in the "closed" state (§7). The row is
  /// still tappable to open detail; only the `+` is disabled.
  final bool         disabled;
  final VoidCallback onTap;
  final VoidCallback? onAdd;      // null → sold-out / closed → `+` disabled
  final VoidCallback onFavourite;

  const _ProductRow({
    required this.product,
    required this.favourite,
    required this.disabled,
    required this.onTap,
    required this.onAdd,
    required this.onFavourite,
  });

  bool get _soldOut => onAdd == null && !disabled;

  @override
  Widget build(BuildContext context) {
    // Spec §11: one Semantics node per row, `+` and heart are separate
    // labelled buttons that stop propagation.
    final rowLabel = [
      product.nameAr,
      if (product.descriptionAr.isNotEmpty) product.descriptionAr,
      ChMoney.format(product.price),
      if (_soldOut) 'نفد',
    ].join('، ');

    return Semantics(
      button: true,
      label: rowLabel,
      onTap: onTap,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D2E1D12), // 0 6px 18px rgba(46,29,18,.05)
                  offset: Offset(0, 6),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── 1) Image (80×80) ──────────────────────
                  _ProductImage(product: product, soldOut: _soldOut),
                  const SizedBox(width: 12),

                  // ── 2) Text column ────────────────────────
                  //
                  // Title / description / price stack cleanly with no
                  // hacky padding — the action buttons live in their own
                  // column on the trailing edge (see 3 below), so nothing
                  // overlaps the text and RTL/LTR just work.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          product.nameAr,
                          style: GoogleFonts.changa(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: CH.ink,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (product.descriptionAr.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3, bottom: 6),
                            child: Text(
                              product.descriptionAr,
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: CH.muted,
                                height: 1.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                ChMoney.format(product.price),
                                style: GoogleFonts.changa(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: CH.hot,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (product.kcal != null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '${product.kcal} سعرة',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFC9B6A6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── 3) Action rail (fixed trailing column) ───
                  //
                  // Heart on top, `+` below — both 36-square pills that
                  // share the same shape language. Fixed width means every
                  // card in the list aligns to the same rail regardless of
                  // title length or missing description.
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 36,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HeartButton(
                          productName: product.nameAr,
                          favourite: favourite,
                          onTap: onFavourite,
                        ),
                        const SizedBox(height: 8),
                        _AddButton(
                          productName: product.nameAr,
                          onAdd: onAdd,
                        ),
                      ],
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

/// 80-square rounded image with the emoji + `cream2` fallback and the
/// sold-out overlay + badge.
class _ProductImage extends StatelessWidget {
  final Product product;
  final bool    soldOut;
  const _ProductImage({required this.product, required this.soldOut});

  @override
  Widget build(BuildContext context) {
    final img = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 80,
        height: 80,
        color: CH.cream2,
        alignment: Alignment.center,
        child: (product.imageUrl == null || product.imageUrl!.isEmpty)
            ? Text(product.emoji, style: const TextStyle(fontSize: 40))
            : Image.network(
                product.imageUrl!,
                fit: BoxFit.cover,
                width: 80,
                height: 80,
                errorBuilder: (_, __, ___) => Text(
                  product.emoji,
                  style: const TextStyle(fontSize: 40),
                ),
                loadingBuilder: (_, child, evt) {
                  if (evt == null) return child;
                  return Text(
                    product.emoji,
                    style: const TextStyle(fontSize: 40),
                  );
                },
              ),
      ),
    );

    if (!soldOut) return img;

    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0.5, child: img),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: CH.char,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'نفد',
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Product-row action buttons.
//
//  Heart (top) and `+` (bottom) share the same 36-square footprint, the
//  same 11-radius, and the same visual weight — deliberately siblings so
//  they read as a single action rail instead of two floating icons.
//
//  Colour language is the only thing that separates them:
//    Heart · white fill · 1.5 `line` border · `hot` glyph when filled
//    Plus  · `char` fill · `paper` glyph
//
//  Both keep a 40-square hit box (Material spec accessibility floor) by
//  sitting inside a SizedBox that's centred by the rail Column.
// ══════════════════════════════════════════════════════════════════
const double _kActionSize   = 36;
const double _kActionRadius = 11;

class _AddButton extends StatefulWidget {
  final String productName;
  final VoidCallback? onAdd;
  const _AddButton({required this.productName, required this.onAdd});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _handle() {
    _press.forward().then((_) => _press.reverse());
    widget.onAdd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onAdd == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'أضف ${widget.productName} للسلة',
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, child) {
          final scale = 1 - (_press.value * 0.04);
          return Transform.scale(scale: scale, child: child);
        },
        child: Material(
          color: disabled ? CH.line : CH.char,
          borderRadius: BorderRadius.circular(_kActionRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(_kActionRadius),
            onTap: disabled ? null : _handle,
            splashColor: Colors.white.withValues(alpha: 0.14),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: SizedBox(
              width: _kActionSize, height: _kActionSize,
              child: Icon(
                Icons.add,
                size: 20,
                color: disabled ? CH.inactive : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeartButton extends StatefulWidget {
  final String       productName;
  final bool         favourite;
  final VoidCallback onTap;
  const _HeartButton({
    required this.productName,
    required this.favourite,
    required this.onTap,
  });

  @override
  State<_HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends State<_HeartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handle() {
    HapticFeedback.selectionClick();
    // Pop only on ADD — removing shouldn't reward the tap.
    if (!widget.favourite) {
      _pop.forward(from: 0).then((_) => _pop.reverse());
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: widget.favourite,
      label: widget.favourite
          ? 'احذف ${widget.productName} من المفضلة'
          : 'أضف ${widget.productName} للمفضلة',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kActionRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_kActionRadius),
          onTap: _handle,
          splashColor: CH.hot.withValues(alpha: 0.10),
          highlightColor: CH.hot.withValues(alpha: 0.06),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_kActionRadius),
              border: Border.all(color: CH.line, width: 1.5),
            ),
            child: SizedBox(
              width: _kActionSize, height: _kActionSize,
              child: Center(
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1, end: 1.25).animate(
                    CurvedAnimation(parent: _pop, curve: Curves.easeOut),
                  ),
                  // Crossfade filled/outlined so the transition reads even
                  // when the pop is subtle (removal case).
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (c, a) =>
                        FadeTransition(opacity: a, child: c),
                    child: Icon(
                      widget.favourite ? Icons.favorite : Icons.favorite_border,
                      key: ValueKey(widget.favourite),
                      size: 18,
                      color: widget.favourite ? CH.hot : CH.inactive,
                    ),
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
//  §3 — Icon box button (40×40, white fill, 1.5 line border, r12).
//  Optional hot dot at top-trailing for the favourites variant.
// ══════════════════════════════════════════════════════════════════
class _IconBoxButton extends StatelessWidget {
  final String       glyph;
  final String       semanticLabel;
  final bool         dot;
  final VoidCallback onTap;

  const _IconBoxButton({
    required this.glyph,
    required this.semanticLabel,
    required this.onTap,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: 44, height: 44,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  child: Container(
                    width: 40, height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: CH.line, width: 1.5),
                    ),
                    child: Text(
                      glyph,
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ),
              if (dot)
                const PositionedDirectional(
                  top: -1, end: -1,
                  child: SizedBox(
                    width: 8, height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: CH.hot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  §7 — Empty category block.
// ══════════════════════════════════════════════════════════════════
class _EmptyCategoryBlock extends StatelessWidget {
  final VoidCallback onSeeAll;
  const _EmptyCategoryBlock({required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🍽️', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(
            'ما في أصناف بهذا القسم حالياً',
            textAlign: TextAlign.center,
            style: GoogleFonts.changa(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: CH.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'جرّب قسم تاني أو رجّع بعد قليل',
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: CH.muted,
            ),
          ),
          const SizedBox(height: 18),
          Material(
            color: CH.char,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onSeeAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                child: Text(
                  'شوف كل الأصناف',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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

// ══════════════════════════════════════════════════════════════════
//  §7 — Error card + retry.
// ══════════════════════════════════════════════════════════════════
class _ErrorCard extends StatelessWidget {
  final String       msg;
  final VoidCallback onRetry;
  const _ErrorCard({required this.msg, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x1AE11D2A),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          const Text('⚠️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: CH.red,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'إعادة المحاولة',
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: CH.hot,
              ),
            ),
          ),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════
//  §7 — Offline / Closed notice card.
// ══════════════════════════════════════════════════════════════════
class _NoticeCard extends StatelessWidget {
  final Color  color;
  final Color  textColor;
  final String text;
  const _NoticeCard({
    required this.color,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  §7 — Skeleton row (5 shown while first page loads).
//  No shimmer package in the repo — mirror Home's static approach.
// ══════════════════════════════════════════════════════════════════
class _ProductRowSkeleton extends StatelessWidget {
  const _ProductRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: CH.cream2,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SkelBar(widthFactor: 0.6),
              SizedBox(height: 8),
              _SkelBar(widthFactor: 0.9),
              SizedBox(height: 8),
              _SkelBar(widthFactor: 0.35),
            ],
          ),
        ),
      ]),
    );
  }
}

class _SkelBar extends StatelessWidget {
  final double widthFactor;
  const _SkelBar({required this.widthFactor});

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: Container(
          height: 10,
          decoration: BoxDecoration(
            color: CH.cream2,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      );
}
