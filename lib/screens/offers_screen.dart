import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/cart_controller.dart';
import '../controllers/offers_controller.dart';
import '../controllers/orders_controller.dart';
import '../models/models.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import '../utils/ch_routes.dart';
import '../widgets/widgets.dart';
import 'app_shell.dart';
import 'offer_detail_screen.dart';

/// Screen 16 — Offers & coupons (العروض والكوبونات).
///
/// Two audiences on one screen: a hero deal you can add to cart like any
/// product, and a browsable list of coupon codes. Entered from three places:
///  - Home offer banner (browse)
///  - Profile 🎟️ tile (browse)
///  - Checkout coupon row → `pickMode: true` (returns a [Coupon] via `pop`)
class OffersScreen extends StatefulWidget {
  final bool pickMode;
  const OffersScreen({super.key, this.pickMode = false});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm       = context.read<OffersController>();
      final cart     = context.read<CartController>();
      final orders   = context.read<OrdersController>();
      vm.ensureLoaded(
        subtotalSyp:   cart.totals.subtotal,
        hasPriorOrders: orders.historyOrders.isNotEmpty,
      );
    });
  }

  void _addHeroToCart(Offer hero) {
    HapticFeedback.lightImpact();
    // Both the '+' button and the card tap open the offer detail screen —
    // that screen owns the "add to cart" action so options + offer price
    // are handled correctly by the bridge.
    _openDetail(hero);
  }

  void _openDetail(Offer hero) {
    Navigator.of(context).push(
      ChRoutes.slideUpFade((_) => OfferDetailScreen(offer: hero)),
    );
  }

  Future<void> _onCouponTap(Coupon c) async {
    final vm = context.read<OffersController>();
    if (widget.pickMode) {
      HapticFeedback.selectionClick();
      vm.select(c);
      return;
    }
    final ok = await vm.copy(c);
    if (!mounted) return;
    HapticFeedback.lightImpact();
    _snack(ok ? 'تم نسخ الكود' : 'تعذّر النسخ — جرّب مرة تانية');
  }

  void _applyPickedCoupon() {
    final vm = context.read<OffersController>();
    final selected = vm.selected;
    if (selected == null) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).pop<Coupon>(selected);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.fromLTRB(16, 0, 16, widget.pickMode ? 120 : 26),
        duration: const Duration(milliseconds: 2000),
      ));
  }

  Future<void> _refresh() async {
    final cart   = context.read<CartController>();
    final orders = context.read<OrdersController>();
    await context.read<OffersController>().refresh(
      subtotalSyp:   cart.totals.subtotal,
      hasPriorOrders: orders.historyOrders.isNotEmpty,
    );
  }

  void _openMenu() {
    // Pop the Offers page and swap the shell to the Menu tab.
    Navigator.of(context).maybePop();
    AppShell.switchTo(context, 1);
  }

  @override
  Widget build(BuildContext context) {
    final vm   = context.watch<OffersController>();
    final cart = context.watch<CartController>();
    final orders = context.watch<OrdersController>();
    final rtl  = Directionality.of(context) == TextDirection.rtl;

    // Refresh the client-side sort when the subtotal changes while the
    // screen is up (adding items on another tab, opening from Checkout).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      vm.resortForCart(
        subtotalSyp:   cart.totals.subtotal,
        hasPriorOrders: orders.historyOrders.isNotEmpty,
      );
    });

    final subtotal       = cart.totals.subtotal;
    final hasPriorOrders = orders.historyOrders.isNotEmpty;
    final bottomInset    = widget.pickMode ? 120.0 : 26.0;

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
          child: Stack(children: [
            ListView(
              padding: EdgeInsets.only(top: 54 + 8, bottom: bottomInset),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // ── Header ───────────────────────────────────
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 14),
                  child: Row(children: [
                    _IconBoxButton(
                      glyph: rtl ? '→' : '←',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Text('العروض',
                      style: GoogleFonts.changa(
                        fontSize: 25, fontWeight: FontWeight.w800, color: CH.ink)),
                  ]),
                ),

                // ── Body ─────────────────────────────────────
                if (vm.loading && !vm.hasAnyContent) ...[
                  const _LoadingHero(),
                  const SizedBox(height: 20),
                  for (int i = 0; i < 3; i++) const _LoadingCouponRow(),
                ] else if (vm.hasError && !vm.hasAnyContent) ...[
                  _ErrorCard(msg: vm.error!, onRetry: _refresh),
                ] else if (!vm.hasAnyContent) ...[
                  const SizedBox(height: 80),
                  ChEmptyState(
                    emoji:    '🎟️',
                    title:    'ما في عروض هلق',
                    subtitle: 'تابعنا — العروض تنزل كل أسبوع.',
                    ctaLabel: 'تصفّح المنيو',
                    onCta:    _openMenu,
                  ),
                ] else ...[
                  if (vm.hasError)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                      child: _OfflineNotice(msg: vm.error!),
                    ),

                  // ── Hero deal card ─────────────────────────
                  if (vm.hero != null)
                    _FadeUp(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                        child: _HeroDealCard(
                          deal:   vm.hero!,
                          onAdd:  () => _addHeroToCart(vm.hero!),
                          onTap:  () => _openDetail(vm.hero!),
                        ),
                      ),
                    ),

                  // ── Secondary deals ────────────────────────
                  for (final d in vm.secondaryDeals)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                      child: _SecondaryDealCard(
                        deal:  d,
                        onAdd: () => _addHeroToCart(d),
                        onTap: () => _openDetail(d),
                      ),
                    ),

                  // ── Coupons section ────────────────────────
                  if (vm.coupons.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 10),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('كوبونات متاحة',
                          style: GoogleFonts.changa(
                            fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink)),
                      ),
                    ),
                    for (int i = 0; i < vm.coupons.length; i++)
                      _StaggerEnter(
                        // Spec §6: stagger 40 ms apart, first 4 only.
                        delay: Duration(milliseconds: i < 4 ? i * 40 : 0),
                        stagger: i < 4,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                          child: _OfferCouponRow(
                            coupon:   vm.coupons[i],
                            pickMode: widget.pickMode,
                            selected: widget.pickMode &&
                                vm.coupons[i].code == vm.selectedCode,
                            eligible: vm.coupons[i].eligibleFor(
                              subtotalSyp:   subtotal,
                              hasPriorOrders: hasPriorOrders,
                            ),
                            reason: vm.coupons[i].reasonAr(
                              subtotalSyp:   subtotal,
                              hasPriorOrders: hasPriorOrders,
                            ),
                            onTap: () => _onCouponTap(vm.coupons[i]),
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),

            // ── Picker CTA bar ─────────────────────────────
            if (widget.pickMode)
              Align(
                alignment: Alignment.bottomCenter,
                child: ChBottomActionBar(
                  child: ChPrimaryButton(
                    label: 'طبّق الكوبون',
                    onPressed: vm.selectedCode == null ? null : _applyPickedCoupon,
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Header icon box — 40×40, white, 1.5px line border, radius 12
// ══════════════════════════════════════════════════════════════════
class _IconBoxButton extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  const _IconBoxButton({required this.glyph, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, label: 'رجوع',
      child: SizedBox(
        width: 44, height: 44,
        child: Center(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CH.line, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(glyph,
                  style: GoogleFonts.cairo(
                    fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Hero deal card (§3)
// ══════════════════════════════════════════════════════════════════
class _HeroDealCard extends StatefulWidget {
  final Offer deal;
  final VoidCallback onAdd;
  final VoidCallback onTap;
  const _HeroDealCard({
    required this.deal, required this.onAdd, required this.onTap,
  });

  @override
  State<_HeroDealCard> createState() => _HeroDealCardState();
}

class _HeroDealCardState extends State<_HeroDealCard> {
  Timer? _tick;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _recompute();
    // Countdown ticks per second only when we're inside 48h.
    if (_showCountdown) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(_recompute);
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _recompute() {
    final ends = widget.deal.endsAt;
    if (ends == null) {
      _left = Duration.zero;
      return;
    }
    _left = ends.difference(DateTime.now());
  }

  bool get _showCountdown {
    final ends = widget.deal.endsAt;
    if (ends == null) return false;
    final diff = ends.difference(DateTime.now());
    return diff.inHours >= 0 && diff.inHours < 48;
  }

  bool get _ended => widget.deal.endsAt != null && _left.isNegative;

  @override
  Widget build(BuildContext context) {
    final d      = widget.deal;
    final ended  = _ended;
    final bg     = ended ? CH.char : CH.hot;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: ended ? null : widget.onTap,
        splashColor: CH.hotDeep.withValues(alpha: 0.25),
        child: Ink(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
          child: Stack(children: [
            // Radial darkening at the trailing-bottom corner.
            const PositionedDirectional(
              bottom: -60, end: -60, width: 220, height: 220,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x40000000), Colors.transparent],
                      stops: [0.0, 0.6],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _KickerPill(text: d.kickerAr),
                          const SizedBox(height: 10),
                          Text(d.titleAr,
                            style: GoogleFonts.changa(
                              fontSize: 22, fontWeight: FontWeight.w800,
                              color: Colors.white, height: 1.2),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (d.descriptionAr != null && d.descriptionAr!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(d.descriptionAr!,
                              style: GoogleFonts.cairo(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: const Color(0xFFFFE6D8), height: 1.6),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 10),
                          _PriceRow(
                            oldPrice: d.originalPrice,
                            newPrice: d.price,
                          ),
                        ],
                      )),
                      const SizedBox(width: 14),
                      _HeroImage(deal: d),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _HeroCta(
                    label:    ended ? 'انتهى العرض' : 'أضف العرض للسلة',
                    onTap:    ended ? null : widget.onAdd,
                  ),
                  if (_showCountdown && !ended) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      // §9 asks for once-per-minute updates for a11y; the
                      // visible text still ticks per second.
                      label: 'ينتهي بعد ${_left.inMinutes} دقيقة',
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          'ينتهي بعد ${_fmtCountdown(_left)}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            fontSize: 12, fontWeight: FontWeight.w800,
                            color: const Color(0xFFFFE6D8)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _KickerPill extends StatelessWidget {
  final String text;
  const _KickerPill({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(
          color: CH.yellow, borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        child: Text(text,
          style: GoogleFonts.cairo(
            fontSize: 11, fontWeight: FontWeight.w800, color: CH.char)),
      );
}

class _PriceRow extends StatelessWidget {
  final int? oldPrice;
  final int  newPrice;
  const _PriceRow({required this.oldPrice, required this.newPrice});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (oldPrice != null) ...[
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(ChMoney.format(oldPrice!),
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: const Color(0xFFFFD0BB),
                  decoration: TextDecoration.lineThrough,
                  decorationColor: const Color(0xFFFFD0BB),
                )),
            ),
            const SizedBox(width: 8),
          ],
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(ChMoney.format(newPrice),
              style: GoogleFonts.changa(
                fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ],
      );
}

class _HeroImage extends StatelessWidget {
  final Offer deal;
  const _HeroImage({required this.deal});
  @override
  Widget build(BuildContext context) {
    final img = deal.imageUrl;
    return SizedBox(
      width: 86, height: 110,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: (img == null || img.isEmpty)
            ? Container(
                color: CH.cream2,
                alignment: Alignment.center,
                child: Text(deal.emoji, style: const TextStyle(fontSize: 56)))
            : Image.network(img,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: CH.cream2,
                  alignment: Alignment.center,
                  child: Text(deal.emoji, style: const TextStyle(fontSize: 56)),
                ),
              ),
      ),
    );
  }
}

class _HeroCta extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _HeroCta({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: disabled ? CH.brown : CH.char,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(label,
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: disabled ? CH.inactive : Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Secondary deal card — 80% scale, white fill, 1.5px hot border,
//  hot title, char CTA (§3 last paragraph)
// ══════════════════════════════════════════════════════════════════
class _SecondaryDealCard extends StatelessWidget {
  final Offer deal;
  final VoidCallback onAdd;
  final VoidCallback onTap;
  const _SecondaryDealCard({
    required this.deal, required this.onAdd, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: CH.hot, width: 1.5),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Smaller image at 64×82 (§10)
              SizedBox(
                width: 64, height: 82,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: (deal.imageUrl == null || deal.imageUrl!.isEmpty)
                      ? Container(color: CH.cream2, alignment: Alignment.center,
                          child: Text(deal.emoji, style: const TextStyle(fontSize: 40)))
                      : Image.network(deal.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: CH.cream2, alignment: Alignment.center,
                            child: Text(deal.emoji, style: const TextStyle(fontSize: 40)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(deal.titleAr,
                    style: GoogleFonts.changa(
                      fontSize: 16, fontWeight: FontWeight.w800, color: CH.hot),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      if (deal.originalPrice != null) ...[
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(ChMoney.format(deal.originalPrice!),
                            style: GoogleFonts.cairo(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: CH.muted,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: CH.muted,
                            )),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(ChMoney.format(deal.price),
                          style: GoogleFonts.changa(
                            fontSize: 15, fontWeight: FontWeight.w800, color: CH.hot)),
                      ),
                    ],
                  ),
                ],
              )),
              const SizedBox(width: 10),
              Material(
                color: CH.char,
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  onTap: onAdd,
                  borderRadius: BorderRadius.circular(11),
                  child: const SizedBox(
                    width: 40, height: 40,
                    child: Icon(Icons.add, color: Colors.white, size: 22),
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
//  Coupon row (§4) — browse + picker modes
// ══════════════════════════════════════════════════════════════════
class _OfferCouponRow extends StatelessWidget {
  final Coupon              coupon;
  final bool                pickMode;
  final bool                selected;
  final CouponIneligibility eligible;
  final String?             reason;
  final VoidCallback        onTap;

  const _OfferCouponRow({
    required this.coupon,
    required this.pickMode,
    required this.selected,
    required this.eligible,
    required this.reason,
    required this.onTap,
  });

  bool get _ineligible => eligible != CouponIneligibility.none;

  @override
  Widget build(BuildContext context) {
    final opacity   = _ineligible ? 0.6 : 1.0;
    final condition = _ineligible
        ? (reason ?? '')
        : (coupon.descriptionAr ?? '');

    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: CH.paper,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ChShadows.card,
        border: (pickMode && selected)
            ? Border.all(color: CH.hot, width: 1.5)
            : null,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        _ValueTile(coupon: coupon),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(coupon.titleAr,
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w800, color: CH.ink),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            if (condition.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(condition,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: _ineligible ? FontWeight.w700 : FontWeight.w600,
                  color: _ineligible ? CH.red : CH.muted,
                  height: 1.4,
                ),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (coupon.endsAt != null) ...[
              const SizedBox(height: 4),
              _ExpiryLine(endsAt: coupon.endsAt!, expiringToday: coupon.isExpiringToday),
            ],
          ],
        )),
        const SizedBox(width: 10),
        if (pickMode)
          _PickerRadio(selected: selected, enabled: !_ineligible)
        else
          _CodeBox(code: coupon.code, onTap: onTap),
      ]),
    );

    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: (pickMode && _ineligible) ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: row,
        ),
      ),
    );
  }
}

class _ValueTile extends StatelessWidget {
  final Coupon coupon;
  const _ValueTile({required this.coupon});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56, height: 56,
      decoration: const BoxDecoration(
        color: CH.cream,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(coupon.valueGlyph,
              style: GoogleFonts.changa(
                fontSize: 18, fontWeight: FontWeight.w800, color: CH.hot)),
          ),
          const SizedBox(height: 3),
          Text(coupon.valueSubAr,
            style: GoogleFonts.cairo(
              fontSize: 9, fontWeight: FontWeight.w700, color: CH.muted)),
        ],
      ),
    );
  }
}

class _ExpiryLine extends StatelessWidget {
  final DateTime endsAt;
  final bool     expiringToday;
  const _ExpiryLine({required this.endsAt, required this.expiringToday});
  @override
  Widget build(BuildContext context) {
    final text = expiringToday
        ? '⏳ ينتهي اليوم'
        : '⏳ ينتهي ${endsAt.day} ${_month(endsAt.month)}';
    return Text(text,
      style: GoogleFonts.cairo(
        fontSize: 11, fontWeight: FontWeight.w600,
        color: expiringToday ? CH.red : const Color(0xFFC9B6A6)),
    );
  }

  static String _month(int m) => switch (m) {
        1  => 'كانون الثاني', 2  => 'شباط',       3  => 'آذار',
        4  => 'نيسان',        5  => 'أيار',       6  => 'حزيران',
        7  => 'تموز',         8  => 'آب',         9  => 'أيلول',
        10 => 'تشرين الأول',  11 => 'تشرين الثاني', 12 => 'كانون الأول',
        _  => '',
      };
}

class _CodeBox extends StatelessWidget {
  final String code;
  final VoidCallback onTap;
  const _CodeBox({required this.code, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: CH.hot, radius: 10, dashWidth: 4, dashSpace: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(code,
              style: GoogleFonts.cairo(
                fontSize: 12, fontWeight: FontWeight.w800, color: CH.hot)),
          ),
        ),
      ),
    );
  }
}

class _PickerRadio extends StatelessWidget {
  final bool selected;
  final bool enabled;
  const _PickerRadio({required this.selected, required this.enabled});
  @override
  Widget build(BuildContext context) {
    final ringColor = enabled
        ? (selected ? CH.hot : CH.radioBorder)
        : CH.inactive;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 22, height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: selected ? 6 : 2),
        color: Colors.white,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Loading, error, offline states
// ══════════════════════════════════════════════════════════════════
class _LoadingHero extends StatelessWidget {
  const _LoadingHero();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
      child: Container(
        height: 172,
        decoration: BoxDecoration(
          color: CH.hot.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 120, height: 12, color: Colors.white24),
            const SizedBox(height: 14),
            Container(width: double.infinity, height: 12, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}

class _LoadingCouponRow extends StatelessWidget {
  const _LoadingCouponRow();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: CH.paper,
          borderRadius: BorderRadius.circular(18),
          boxShadow: ChShadows.card,
        ),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(width: 56, height: 56,
            decoration: BoxDecoration(
              color: CH.cream2, borderRadius: BorderRadius.circular(16))),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 160, height: 12, color: CH.cream2),
              const SizedBox(height: 8),
              Container(width: 110, height: 10, color: CH.cream2),
              const SizedBox(height: 8),
              Container(width: 80,  height: 10, color: CH.cream2),
            ],
          )),
        ]),
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  final String msg;
  const _OfflineNotice({required this.msg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: CH.cream2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Text('📡', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text(msg,
            style: GoogleFonts.cairo(
              fontSize: 12, fontWeight: FontWeight.w700, color: CH.ink))),
        ]),
      );
}

class _ErrorCard extends StatelessWidget {
  final String msg;
  final Future<void> Function() onRetry;
  const _ErrorCard({required this.msg, required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 60, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x1AE11D2A),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: [
            const Text('⚠️', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.w700, color: CH.red)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: Text('إعادة المحاولة',
                style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.w800, color: CH.hot)),
            ),
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  Motion: enter fade-up (hero) + per-item stagger (coupon rows)
// ══════════════════════════════════════════════════════════════════
class _FadeUp extends StatefulWidget {
  final Widget child;
  const _FadeUp({required this.child});
  @override
  State<_FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<_FadeUp> {
  double _opacity = 0;
  double _dy      = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() { _opacity = 1; _dy = 0; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: Offset(0, _dy / 100),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _StaggerEnter extends StatefulWidget {
  final Widget   child;
  final Duration delay;
  final bool     stagger;
  const _StaggerEnter({
    required this.child, required this.delay, required this.stagger,
  });
  @override
  State<_StaggerEnter> createState() => _StaggerEnterState();
}

class _StaggerEnterState extends State<_StaggerEnter> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.stagger) { _opacity = 1; return; }
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) || !widget.stagger) {
      return widget.child;
    }
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Dashed border painter — used by the browse-mode code box
// ══════════════════════════════════════════════════════════════════
class _DashedBorderPainter extends CustomPainter {
  final Color  color;
  final double radius;
  final double dashWidth;
  final double dashSpace;
  _DashedBorderPainter({
    required this.color, required this.radius,
    required this.dashWidth, required this.dashSpace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rect);
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      double dist = 0;
      while (dist < m.length) {
        final next = dist + dashWidth;
        canvas.drawPath(m.extractPath(dist, next.clamp(0, m.length)), paint);
        dist = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter o) =>
      o.color != color || o.radius != radius ||
      o.dashWidth != dashWidth || o.dashSpace != dashSpace;
}

// ══════════════════════════════════════════════════════════════════
//  Helpers
// ══════════════════════════════════════════════════════════════════
String _fmtCountdown(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

