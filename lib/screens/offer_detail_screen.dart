import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/cart_controller.dart';
import '../models/models.dart';
import '../services/catalog_service.dart';
import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import '../utils/ch_routes.dart';
import 'app_shell.dart';
import 'detail_screen.dart';

/// Dedicated screen for a single offer.
///
/// Shows the deal (hero image, title, description, old vs new price, savings,
/// expiry countdown) with a single CTA. Fetches the linked product on open
/// so the CTA can route correctly:
///
///  * Product has option groups → bridge to [DetailScreen] with `fromOffer`
///    so the customer picks options at the offer price.
///  * Product has no option groups → add to cart directly at the offer price
///    (server validates + prices via the `offer_id` on the cart line).
///  * No linked product → CTA is disabled and a note explains the offer is
///    informational only.
class OfferDetailScreen extends StatefulWidget {
  final Offer offer;
  const OfferDetailScreen({super.key, required this.offer});

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  Product? _product;      // resolved from /products/{slug}
  bool     _loading = false;
  bool     _adding  = false;
  String?  _fetchError;   // shown inline when /products/{slug} fails
  Timer?   _tick;
  Duration _timeLeft = Duration.zero;

  Offer get _o => widget.offer;

  @override
  void initState() {
    super.initState();
    _recomputeTimer();
    _startCountdownIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchProduct());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _showCountdown {
    final ends = _o.endsAt;
    if (ends == null) return false;
    final diff = ends.difference(DateTime.now());
    return diff.inHours >= 0 && diff.inHours < 48;
  }

  bool get _ended => _o.endsAt != null && _timeLeft.isNegative;

  void _recomputeTimer() {
    final ends = _o.endsAt;
    _timeLeft = ends == null ? Duration.zero : ends.difference(DateTime.now());
  }

  void _startCountdownIfNeeded() {
    if (!_showCountdown) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_recomputeTimer);
    });
  }

  Future<void> _fetchProduct() async {
    final slug = _o.productSlug;
    if (slug == null || slug.isEmpty) return;
    setState(() {
      _loading    = true;
      _fetchError = null;
    });
    try {
      final fresh = await context.read<CatalogService>().getBySlug(slug);
      if (!mounted) return;
      setState(() => _product = fresh);
    } catch (e) {
      if (!mounted) return;
      setState(() => _fetchError = 'ما قدرنا نجيب تفاصيل العرض. جرّب مرة تانية.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onCta() async {
    if (_ended || _adding) return;

    // No linked product → tell the user why the offer can't be added, instead
    // of a silent disabled tap.
    final slug = _o.productSlug;
    if (slug == null || slug.isEmpty) {
      _toast('هذا العرض للعرض فقط — تواصل مع المطعم للطلب');
      return;
    }

    final product = _product;
    if (product == null) {
      // Fetch still in flight or failed. Retry once, then bail with a message.
      if (_loading) {
        _toast('لحظة، جاري تحميل تفاصيل العرض...');
        return;
      }
      await _fetchProduct();
      if (_product == null) {
        _toast(_fetchError ?? 'ما قدرنا نجيب تفاصيل العرض. جرّب مرة تانية.');
        return;
      }
    }

    if (!mounted) return;
    HapticFeedback.mediumImpact();

    // If the product has option groups, bridge to Detail so the customer picks
    // spice / size / addons; the offer price + offer_id ride along via
    // `fromOffer`. Otherwise add directly here at the offer price.
    if (_product!.optionGroups.isNotEmpty) {
      Navigator.of(context).push(
        ChRoutes.slideUpFade((_) => DetailScreen(
              product: _product!,
              fromOffer: _o,
            )),
      );
      return;
    }

    setState(() => _adding = true);
    if (!mounted) return;
    context.read<CartController>().add(_product!, offer: _o);
    if (!mounted) return;
    setState(() => _adding = false);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          'أُضيف العرض للسلة',
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        duration: const Duration(milliseconds: 2500),
        action: SnackBarAction(
          label: 'عرض السلة',
          textColor: CH.hot,
          onPressed: () {
            Navigator.of(context).maybePop();
            AppShell.switchTo(context, 2);
          },
        ),
      ));
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg,
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        backgroundColor: CH.char,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        duration: const Duration(milliseconds: 2200),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final rtl        = Directionality.of(context) == TextDirection.rtl;
    final savings    = _o.savings;
    final hasProduct = _o.productSlug != null && _o.productSlug!.isNotEmpty;

    final ctaLabel = _ended
        ? 'انتهى العرض'
        : (!hasProduct
            ? 'للعرض فقط'
            : (_loading
                ? 'لحظة...'
                : (_product?.optionGroups.isNotEmpty ?? false)
                    ? 'اختر الخيارات'
                    : 'أضف العرض للسلة'));
    // Always tappable except when the offer has ended or an add is in flight.
    // `_onCta` surfaces a toast if the product isn't ready — that's a much
    // clearer failure mode than a dead disabled button.
    final ctaEnabled = !_ended && !_adding;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        extendBodyBehindAppBar: true,
        body: Column(children: [
          _OfferHero(
            offer:  _o,
            isRtl:  rtl,
            onBack: () => Navigator.of(context).maybePop(),
          ),
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
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                  children: [
                    _KickerPill(text: _o.kickerAr),
                    const SizedBox(height: 12),
                    Text(_o.titleAr,
                      style: GoogleFonts.changa(
                        fontSize: 24, fontWeight: FontWeight.w800, color: CH.ink,
                        height: 1.25)),
                    if (_o.productName != null && _o.productName!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('يشمل: ${_o.productName}',
                        style: GoogleFonts.cairo(
                          fontSize: 13, fontWeight: FontWeight.w700, color: CH.muted)),
                    ],
                    const SizedBox(height: 12),
                    _PriceBlock(
                      offerPrice:    _o.price,
                      originalPrice: _o.originalPrice,
                      savings:       savings,
                    ),
                    if (_o.descriptionAr != null && _o.descriptionAr!.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(_o.descriptionAr!,
                        style: GoogleFonts.cairo(
                          fontSize: 14, height: 1.8,
                          color: const Color(0xFF6D5D51))),
                    ],
                    if (_showCountdown && !_ended) ...[
                      const SizedBox(height: 18),
                      _CountdownStrip(left: _timeLeft),
                    ] else if (_o.endsAt != null && !_ended) ...[
                      const SizedBox(height: 18),
                      _EndsAtLine(endsAt: _o.endsAt!),
                    ],
                    if (!hasProduct) ...[
                      const SizedBox(height: 18),
                      _InfoStrip(
                        emoji: 'ℹ️',
                        text: 'هذا العرض للعرض فقط — تواصل مع المطعم للطلب.',
                      ),
                    ] else if (_fetchError != null) ...[
                      const SizedBox(height: 18),
                      _InfoStrip(emoji: '⚠️', text: _fetchError!),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _BottomBar(
            label:   ctaLabel,
            total:   _o.price,
            enabled: ctaEnabled,
            onTap:   _onCta,
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Hero image + back button
// ═════════════════════════════════════════════════════════════════
class _OfferHero extends StatelessWidget {
  final Offer offer;
  final bool  isRtl;
  final VoidCallback onBack;
  const _OfferHero({required this.offer, required this.isRtl, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final img = offer.imageUrl;
    return SizedBox(
      height: 300, width: double.infinity,
      child: Stack(children: [
        Positioned.fill(
          child: (img == null || img.isEmpty)
              ? Container(
                  color: CH.cream2,
                  alignment: Alignment.center,
                  child: Text(offer.emoji, style: const TextStyle(fontSize: 220)),
                )
              : Image.network(img,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: CH.cream2,
                    alignment: Alignment.center,
                    child: Text(offer.emoji, style: const TextStyle(fontSize: 220)),
                  ),
                ),
        ),
        PositionedDirectional(
          top: 58, start: 16,
          child: Semantics(
            button: true, label: 'رجوع',
            child: Material(
              color: Colors.white.withValues(alpha: 0.94),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onBack,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 40, height: 40,
                  child: Center(
                    child: Text(isRtl ? '→' : '←',
                      style: GoogleFonts.cairo(
                        fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
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
          color: CH.yellow,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        child: Text(text,
          style: GoogleFonts.cairo(
            fontSize: 11, fontWeight: FontWeight.w800, color: CH.char)),
      );
}

class _PriceBlock extends StatelessWidget {
  final int  offerPrice;
  final int? originalPrice;
  final int? savings;
  const _PriceBlock({
    required this.offerPrice,
    required this.originalPrice,
    required this.savings,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap (not Row) so the savings pill drops to a second line on narrow
    // screens instead of overflowing — long SYP prices + strike + pill exceed
    // most phone widths.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(ChMoney.format(offerPrice),
            style: GoogleFonts.changa(
              fontSize: 30, fontWeight: FontWeight.w800, color: CH.hot)),
        ),
        if (originalPrice != null && originalPrice! > offerPrice)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(ChMoney.format(originalPrice!),
              style: GoogleFonts.cairo(
                fontSize: 15, fontWeight: FontWeight.w700, color: CH.muted,
                decoration: TextDecoration.lineThrough,
                decorationColor: CH.muted,
              )),
          ),
        if (savings != null && savings! > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: CH.hot.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text('توفير ${ChMoney.format(savings!)}',
                style: GoogleFonts.cairo(
                  fontSize: 12, fontWeight: FontWeight.w800, color: CH.hot)),
            ),
          ),
      ],
    );
  }
}

class _CountdownStrip extends StatelessWidget {
  final Duration left;
  const _CountdownStrip({required this.left});
  @override
  Widget build(BuildContext context) {
    final h = left.inHours.toString().padLeft(2, '0');
    final m = (left.inMinutes % 60).toString().padLeft(2, '0');
    final s = (left.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CH.cream2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Text('⏳', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(child: Text('ينتهي بعد',
          style: GoogleFonts.cairo(
            fontSize: 13, fontWeight: FontWeight.w700, color: CH.ink))),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text('$h:$m:$s',
            style: GoogleFonts.changa(
              fontSize: 15, fontWeight: FontWeight.w800, color: CH.hot)),
        ),
      ]),
    );
  }
}

class _EndsAtLine extends StatelessWidget {
  final DateTime endsAt;
  const _EndsAtLine({required this.endsAt});
  @override
  Widget build(BuildContext context) => Text(
        '⏳ ينتهي ${endsAt.day}/${endsAt.month}/${endsAt.year}',
        style: GoogleFonts.cairo(
          fontSize: 12, fontWeight: FontWeight.w700, color: CH.muted),
      );
}

class _InfoStrip extends StatelessWidget {
  final String emoji;
  final String text;
  const _InfoStrip({required this.emoji, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: CH.cream2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
            style: GoogleFonts.cairo(
              fontSize: 13, fontWeight: FontWeight.w700, color: CH.ink))),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════
//  Bottom CTA bar
// ═════════════════════════════════════════════════════════════════
class _BottomBar extends StatelessWidget {
  final String label;
  final int    total;
  final bool   enabled;
  final VoidCallback onTap;
  const _BottomBar({
    required this.label,
    required this.total,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(
        top: 14, left: 20, right: 20, bottom: 20 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: CH.navTopBorder, width: 1)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled ? ChShadows.primaryButton : null,
        ),
        child: Material(
          color: enabled ? CH.hot : CH.brown,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                    style: GoogleFonts.changa(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: enabled ? Colors.white : CH.inactive)),
                  Text('  ·  ',
                    style: GoogleFonts.changa(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: enabled ? Colors.white : CH.inactive)),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(ChMoney.format(total),
                      style: GoogleFonts.changa(
                        fontSize: 16, fontWeight: FontWeight.w800,
                        color: enabled ? Colors.white : CH.inactive)),
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
