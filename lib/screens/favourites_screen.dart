import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/cart_controller.dart';
import '../controllers/favourites_controller.dart';
import '../models/models.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import '../utils/ch_routes.dart';
import 'app_shell.dart';
import 'detail_screen.dart';
import 'login_screen.dart';

/// Screen 09 — Favourites (المفضلة).
///
/// A 2-column grid of the user's saved products, most-recent-first.
/// See `FAVOURITES_SCREEN.md` for the full spec.
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FavouritesController>().ensureLoaded();
    });
  }

  Future<void> _refresh() => context.read<FavouritesController>().refresh();

  void _openDetail(Product p) {
    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => DetailScreen(product: p)),
    );
  }

  void _openMenu() {
    // Empty-state CTA → the Menu tab in the shell.
    Navigator.of(context).maybePop();
    AppShell.switchTo(context, 1);
  }

  void _openLogin() {
    Navigator.of(context).push(
      ChRoutes.slideUpFade(
        (_) => const LoginScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  void _addToCart(Product p) {
    HapticFeedback.lightImpact();
    context.read<CartController>().add(p);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          'أُضيف ${p.nameAr} للسلة',
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 26),
        duration: const Duration(milliseconds: 2000),
      ));
  }

  Future<void> _removeWithUndo(Product p) async {
    final vm = context.read<FavouritesController>();
    // Snapshot the removed index BEFORE the mutation so undo restores in
    // the original slot (spec §6).
    final originalIndex = vm.items.indexWhere((x) => x.id == p.id);

    final result = await vm.toggle(p);

    if (!mounted) return;

    switch (result) {
      case FavouriteToggleResult.removed:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Semantics(
              liveRegion: true,
              child: Text(
                'تم حذف ${p.nameAr} من المفضلة',
                style: GoogleFonts.cairo(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
            backgroundColor: CH.char,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 26),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'تراجع',
              textColor: CH.hot,
              onPressed: () {
                context
                    .read<FavouritesController>()
                    .restoreAt(originalIndex < 0 ? 0 : originalIndex, p);
              },
            ),
          ));
      case FavouriteToggleResult.guest:
        _toast('سجّل دخولك لحفظ المفضلة');
      case FavouriteToggleResult.error:
        _toast('ما قدرنا نحذف الصنف — جرّب مرة تانية');
      case FavouriteToggleResult.added:
      case FavouriteToggleResult.full:
        // Toggle from Favourites screen is always a removal — these branches
        // are just here for exhaustiveness.
        break;
    }
  }

  void _toast(String msg) {
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

  void _openLongPressSheet(Product p) {
    // Long-press actions must also be exposed as CustomSemanticsActions on
    // the card — see [_FavouriteCard.build].
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: CH.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_shopping_cart, color: CH.ink),
              title: Text(
                'أضف للسلة',
                style: GoogleFonts.cairo(
                  fontSize: 15, fontWeight: FontWeight.w800, color: CH.ink),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _addToCart(p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: CH.red),
              title: Text(
                'احذف من المفضلة',
                style: GoogleFonts.cairo(
                  fontSize: 15, fontWeight: FontWeight.w800, color: CH.red),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _removeWithUndo(p);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm  = context.watch<FavouritesController>();
    final rtl = Directionality.of(context) == TextDirection.rtl;

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
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ───── 1) Header (§3) ─────
              SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 54 + 8, 20, 14),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _IconBoxButton(
                        glyph: rtl ? '→' : '←',
                        semanticLabel: 'رجوع',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'المفضلة',
                        style: GoogleFonts.changa(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: CH.ink,
                        ),
                      ),
                      if (vm.count > 6) ...[
                        const Spacer(),
                        Text(
                          _itemCountLabel(vm.count),
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: CH.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ───── 2) Body: loading / error / guest / empty / grid ─────
              _FavouritesBody(
                vm: vm,
                onOpenDetail: _openDetail,
                onAdd: _addToCart,
                onRemove: _removeWithUndo,
                onLongPress: _openLongPressSheet,
                onBrowseMenu: _openMenu,
                onSignIn: _openLogin,
              ),

              // ───── 3) Hint line (§5) — only when 1..3 items ─────
              if (!vm.loading && vm.count >= 1 && vm.count <= 3)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'اضغط على القلب في المنيو لتضيف أصنافك هنا.',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CH.muted,
                        ),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 26)),
            ],
          ),
        ),
      ),
    );
  }

  /// Arabic plural approximation for the trailing count in the header.
  /// A proper ICU form is a TODO — the app has no `l10n` layer yet.
  static String _itemCountLabel(int n) {
    if (n == 1) return 'صنف واحد';
    if (n == 2) return 'صنفان';
    if (n >= 3 && n <= 10) return '$n أصناف';
    return '$n صنف';
  }
}

// ══════════════════════════════════════════════════════════════════
//  Body sliver — dispatches to loading / error / guest / empty / grid.
// ══════════════════════════════════════════════════════════════════
class _FavouritesBody extends StatelessWidget {
  final FavouritesController vm;
  final void Function(Product p) onOpenDetail;
  final void Function(Product p) onAdd;
  final void Function(Product p) onRemove;
  final void Function(Product p) onLongPress;
  final VoidCallback onBrowseMenu;
  final VoidCallback onSignIn;

  const _FavouritesBody({
    required this.vm,
    required this.onOpenDetail,
    required this.onAdd,
    required this.onRemove,
    required this.onLongPress,
    required this.onBrowseMenu,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    // Loading — §8. 4 card skeletons.
    if (vm.loading && vm.items.isEmpty && vm.error == null) {
      return SliverPadding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .78,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, __) => const _FavouriteCardSkeleton(),
            childCount: 4,
          ),
        ),
      );
    }

    // Error — §8.
    if (vm.error != null && vm.items.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _ErrorCard(
            msg: vm.error!,
            onRetry: () => context.read<FavouritesController>().refresh(),
          ),
        ),
      );
    }

    // Guest — §8.
    if (vm.isGuest && vm.items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyBlock(
          emoji: '🤍',
          title: 'سجّل دخولك لحفظ المفضلة',
          body: 'سجّل دخولك لتحفظ مفضلتك على كل أجهزتك',
          ctaLabel: 'تسجيل الدخول',
          ctaColor: CH.hot,
          onCta: onSignIn,
        ),
      );
    }

    // Empty — §8.
    if (vm.items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyBlock(
          emoji: '🤍',
          title: 'ما في أصناف بالمفضلة',
          body: 'اضغط على القلب لتحفظ أصنافك المفضلة.',
          ctaLabel: 'تصفّح المنيو',
          ctaColor: CH.char,
          onCta: onBrowseMenu,
        ),
      );
    }

    // Grid — §4.
    // Clamp text scaling to 1.4× and drop to 1 column above 1.2× (§12).
    final ts = MediaQuery.textScalerOf(context).scale(14) / 14;
    final crossAxisCount = ts > 1.2 ? 1 : 2;
    // The mockup's card at 2 cols is ~166 dp × ~213 dp → ratio 0.78. At 1
    // col the image can dominate — widen the aspect ratio for readability.
    final ratio = crossAxisCount == 2 ? 0.78 : 1.6;

    return SliverPadding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: ratio,
        ),
        delegate: SliverChildBuilderDelegate(
          childCount: vm.items.length,
          (_, i) {
            final p = vm.items[i];
            return _StaggeredEnter(
              delay: Duration(milliseconds: i < 4 ? 40 * i : 0),
              child: _FavouriteCard(
                product:      p,
                onTap:        () => onOpenDetail(p),
                onAdd:        () => onAdd(p),
                onRemove:     () => onRemove(p),
                onLongPress:  () => onLongPress(p),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  §4 — Favourite card.
// ══════════════════════════════════════════════════════════════════
class _FavouriteCard extends StatelessWidget {
  final Product      product;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onLongPress;

  const _FavouriteCard({
    required this.product,
    required this.onTap,
    required this.onAdd,
    required this.onRemove,
    required this.onLongPress,
  });

  // Product model has no `soldOut` field; treat every card as available for
  // now. Wired here so the badge + disabled `+` are ready when the flag
  // lands.
  bool get _soldOut => false;

  @override
  Widget build(BuildContext context) {
    // Long-press exposed as a semantic custom action per §12.
    return Semantics(
      button: true,
      label: [product.nameAr, ChMoney.format(product.price), if (_soldOut) 'نفد']
          .join('، '),
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'أضف للسلة'):    onAdd,
        const CustomSemanticsAction(label: 'احذف من المفضلة'): onRemove,
      },
      child: _PressableCard(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── image + heart overlay ──
            //
            // We `Expanded` the image (rather than force 1:1) so the body
            // never overflows on tight screens or with larger Arabic
            // line-height. The card's outer `childAspectRatio: 0.78` still
            // biases the image toward square — this just guarantees the
            // name + price row always fit.
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _FavImage(product: product, soldOut: _soldOut)),
                  // Heart — mirrored via PositionedDirectional per §11.
                  PositionedDirectional(
                    top: 8,
                    end: 8,
                    child: _FloatingHeart(
                      onTap: onRemove,
                      productName: product.nameAr,
                    ),
                  ),
                ],
              ),
            ),

            // ── body: name + price row ──
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 12, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.nameAr,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: CH.ink,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            ChMoney.format(product.price),
                            style: GoogleFonts.changa(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: CH.hot,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _AddButton(
                        productName: product.nameAr,
                        onAdd: _soldOut ? null : onAdd,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White card with r18 clip, subtle shadow, and a press-scale of 0.98 for
/// the whole card (excluding heart/`+`, which stop propagation).
class _PressableCard extends StatefulWidget {
  final Widget       child;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _PressableCard({
    required this.child,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  double _scale = 1;

  void _down() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    setState(() => _scale = 0.98);
  }

  void _up() {
    if (_scale == 1) return;
    setState(() => _scale = 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   (_) => _down(),
      onTapUp:     (_) => _up(),
      onTapCancel:      _up,
      onTap:            widget.onTap,
      onLongPress:      widget.onLongPress,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F2E1D12),   // 0 6px 18px rgba(46,29,18,.06)
                  offset: Offset(0, 6),
                  blurRadius: 18,
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Fav card image + sold-out overlay.
// ══════════════════════════════════════════════════════════════════
class _FavImage extends StatelessWidget {
  final Product product;
  final bool    soldOut;
  const _FavImage({required this.product, required this.soldOut});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: CH.cream2,
      alignment: Alignment.center,
      child: Text(product.emoji, style: const TextStyle(fontSize: 60)),
    );

    final img = (product.imageUrl == null || product.imageUrl!.isEmpty)
        ? fallback
        : Image.network(
            product.imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
            loadingBuilder: (_, child, evt) => evt == null ? child : fallback,
          );

    if (!soldOut) return Hero(tag: 'product-${product.id}', child: img);

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: 0.5,
            child: Hero(tag: 'product-${product.id}', child: img),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: CH.char,
            borderRadius: BorderRadius.circular(999),
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

/// 28-circle white heart overlay with a 44 hit box.
class _FloatingHeart extends StatelessWidget {
  final String       productName;
  final VoidCallback onTap;
  const _FloatingHeart({required this.productName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: true,
      label: 'احذف $productName من المفضلة',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44, height: 44,
          child: Center(
            child: Container(
              width: 28, height: 28,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1F000000), // 0 2px 8px rgba(0,0,0,.12)
                    offset: Offset(0, 2),
                    blurRadius: 8,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text('❤️', style: TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  30×30 char `+` with `#000` tint on press.
// ══════════════════════════════════════════════════════════════════
class _AddButton extends StatefulWidget {
  final String productName;
  final VoidCallback? onAdd;
  const _AddButton({required this.productName, required this.onAdd});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handle() {
    _ctrl.forward().then((_) => _ctrl.reverse());
    widget.onAdd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onAdd == null;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'أضف ${widget.productName} للسلة',
      child: SizedBox(
        width: 44, height: 44,
        child: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) {
              return Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: disabled
                      ? CH.line
                      : Color.lerp(CH.char, Colors.black, _ctrl.value),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: child,
              );
            },
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: disabled ? null : _handle,
                child: Icon(
                  Icons.add,
                  size: 17,
                  color: disabled ? CH.inactive : Colors.white,
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
//  §3 — 40×40 white icon-box back button.
// ══════════════════════════════════════════════════════════════════
class _IconBoxButton extends StatelessWidget {
  final String       glyph;
  final String       semanticLabel;
  final VoidCallback onTap;
  const _IconBoxButton({
    required this.glyph,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: 44, height: 44,
        child: Center(
          child: Material(
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
                child: Text(glyph, style: const TextStyle(fontSize: 17)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  §8 — Empty / Guest block. Shared shell.
// ══════════════════════════════════════════════════════════════════
class _EmptyBlock extends StatelessWidget {
  final String       emoji;
  final String       title;
  final String       body;
  final String       ctaLabel;
  final Color        ctaColor;
  final VoidCallback onCta;
  const _EmptyBlock({
    required this.emoji,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.ctaColor,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.changa(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: CH.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: CH.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Material(
            color: ctaColor,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: onCta,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                child: Text(
                  ctaLabel,
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
//  §8 — Error card.
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
//  §8 — Loading skeleton.
// ══════════════════════════════════════════════════════════════════
class _FavouriteCardSkeleton extends StatelessWidget {
  const _FavouriteCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Match the real card: image `Expanded`, body natural — this
            // stops the 4px overflow the framework flagged.
            Expanded(child: Container(color: CH.cream2)),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 12, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 10,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: CH.cream2,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 0.4,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: CH.cream2,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  §9 — Fade-up 8dp, 40 ms apart, first 4 only.
// ══════════════════════════════════════════════════════════════════
class _StaggeredEnter extends StatefulWidget {
  final Widget   child;
  final Duration delay;
  const _StaggeredEnter({required this.child, this.delay = Duration.zero});

  @override
  State<_StaggeredEnter> createState() => _StaggeredEnterState();
}

class _StaggeredEnterState extends State<_StaggeredEnter> {
  double _opacity = 0;
  double _dy      = 8;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() { _opacity = 1; _dy = 0; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: Offset(0, _dy / 100),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
