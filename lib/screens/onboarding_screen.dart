import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_prefs.dart';
import '../theme/theme.dart';
import 'login_screen.dart';

/// Screen 02 — Onboarding (شاشة الترحيب).
///
/// Layout (per the reference mock):
///  - Full-bleed `char` canvas, light status icons, portrait-locked.
///  - Media zone (top ~56%) — plain dark backdrop + skip pill top-end.
///    We'll swap in `Image.asset('assets/onboarding/onb_X.jpg', fit: cover)`
///    once the food photographer delivers the shots.
///  - Copy zone (bottom ~44%) — title / body / dots / sticky CTA.
///  - PageView swipe (RTL-aware `reverse`) with 3 Syrian-dialect slides.
///  - Exit sets `AppPrefs.onboardingSeen = true` and fades to Login.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pager = PageController();
  int _i = 0;

  static const _slides = <_Slide>[
    _Slide(
      titleAr: 'دجاج مقرمش يوصلك سخن',
      titleEn: 'Crispy chicken, still hot at your door',
      bodyAr:  'بروستد، شاورما، برجر وساندويشات على أصولها. اطلب بضغطة واتبع طلبك لحد باب البيت.',
      bodyEn:  'Broasted chicken, shawarma, burgers and sandwiches done right. Order in a tap and follow it all the way home.',
      ctaAr:   'يلا نبدأ',
      ctaEn:   'Next',
      // Curated Unsplash food-photography — served portrait-cropped at
      // phone resolution (`h=1600&w=1080`, `q=85`) for crisp, editorial-
      // quality visuals without wasting bandwidth. `errorBuilder` below
      // covers any URL that 404s so the flow never breaks.
      imageUrl: 'https://images.unsplash.com/photo-1562967914-608f82629710?auto=format&fit=crop&h=1600&w=1080&q=85',
      fallbackEmoji: '🍗',
    ),
    _Slide(
      titleAr: 'عروض وكوبونات كل أسبوع',
      titleEn: 'Deals and coupons every week',
      bodyAr:  'وجبات العائلة، 2×1 على الزنجر، وتوصيل مجاني للطلبات الكبيرة.',
      bodyEn:  'Family meals, 2-for-1 Zinger, and free delivery on big orders.',
      ctaAr:   'كمّل',
      ctaEn:   'Next',
      imageUrl: 'https://images.unsplash.com/photo-1571091718767-18b5b1457add?auto=format&fit=crop&h=1600&w=1080&q=85',
      fallbackEmoji: '🍔',
    ),
    _Slide(
      titleAr: 'تتبّع طلبك لحظة بلحظة',
      titleEn: 'Track your order minute by minute',
      bodyAr:  'من المطبخ لعندك — تعرف وين صار طلبك وكم باقي.',
      bodyEn:  'From the kitchen to your door — always know where your order is.',
      ctaAr:   'يلا نبدأ',
      ctaEn:   'Get started',
      imageUrl: 'https://images.unsplash.com/photo-1595854341625-f33ee10dbf94?auto=format&fit=crop&h=1600&w=1080&q=85',
      fallbackEmoji: '🛵',
    ),
  ];

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await AppPrefs.instance.setOnboardingSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  void _next() {
    if (_i >= _slides.length - 1) {
      _finish();
      return;
    }
    _pager.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final isLast   = _i == _slides.length - 1;
    final slide    = _slides[_i];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: CH.char,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: _i == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _pager.previousPage(
            duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
        },
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.4,
          child: Scaffold(
            backgroundColor: CH.char,
            body: SafeArea(
              top: false, bottom: false,
              child: Column(
                children: [
                  // ══════════════════════════════════════════════════════════════
                  //  MEDIA ZONE — flex 56, plain dark backdrop with skip pill
                  // ══════════════════════════════════════════════════════════════
                  Expanded(
                    flex: 56,
                    child: Stack(
                      children: [
                        // Background pager — one media widget per slide.
                        // Swipe is RTL-aware via `reverse: isArabic` so
                        // Arabic users slide right-to-left as expected.
                        PageView.builder(
                          controller: _pager,
                          onPageChanged: (i) => setState(() => _i = i),
                          itemCount: _slides.length,
                          reverse: isArabic,
                          physics: const BouncingScrollPhysics(),
                          itemBuilder: (_, i) => _SlideMedia(slide: _slides[i]),
                        ),

                        // Fade the bottom edge into the copy zone.
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end:   Alignment.topCenter,
                                  stops:  [0.0, 0.35],
                                  colors: [CH.char, Color(0x001A1210)],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Skip pill — top-end (Arabic RTL → top-left of screen)
                        if (!isLast)
                          PositionedDirectional(
                            top: MediaQuery.paddingOf(context).top + 20,
                            end: 18,
                            child: _SkipPill(onTap: _finish),
                          ),
                      ],
                    ),
                  ),

                  // ══════════════════════════════════════════════════════════════
                  //  COPY ZONE — flex 44, title / body / dots / CTA
                  // ══════════════════════════════════════════════════════════════
                  Expanded(
                    flex: 44,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        top: 4, start: 28, end: 28,
                        bottom: 24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title — Changa 800 32 white
                          Semantics(
                            header: true,
                            child: Text(
                              isArabic ? slide.titleAr : slide.titleEn,
                              maxLines: 2,
                              style: GoogleFonts.changa(
                                fontSize: 30, height: 1.25,
                                fontWeight: FontWeight.w800, color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Body — Cairo 400 16 muted
                          Text(
                            isArabic ? slide.bodyAr : slide.bodyEn,
                            maxLines: 3,
                            style: GoogleFonts.cairo(
                              fontSize: 15, height: 1.75,
                              color: const Color(0xFFCBB8A8),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Dots — 26×7 active in `hot`, 7×7 white24 inactive
                          Row(
                            mainAxisAlignment: isArabic
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              for (int j = 0; j < _slides.length; j++) ...[
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 240),
                                  curve: Curves.easeOut,
                                  width:  j == _i ? 26 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: j == _i ? CH.hot : Colors.white24,
                                  ),
                                ),
                                if (j != _slides.length - 1) const SizedBox(width: 7),
                              ],
                            ],
                          ),

                          const Spacer(),

                          // Primary CTA — hot fill, radius 16, orange-tinted shadow
                          SizedBox(
                            width: double.infinity,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x66EE4E1B),
                                    offset: Offset(0, 16),
                                    blurRadius: 34,
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _next,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: CH.hot,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 17),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.all(
                                    CH.hotDeep.withValues(alpha: 0.25)),
                                ),
                                child: Text(
                                  isArabic ? slide.ctaAr : slide.ctaEn,
                                  style: GoogleFonts.changa(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

// ───────────────────────────────────────────────────────────────
//  Slide model
// ───────────────────────────────────────────────────────────────
class _Slide {
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final String ctaAr;
  final String ctaEn;
  final String imageUrl;
  final String fallbackEmoji;

  const _Slide({
    required this.titleAr, required this.titleEn,
    required this.bodyAr,  required this.bodyEn,
    required this.ctaAr,   required this.ctaEn,
    required this.imageUrl,
    required this.fallbackEmoji,
  });
}

// ───────────────────────────────────────────────────────────────
//  Slide media — full-bleed photo with two clearly separate states:
//
//  • Loading (from `loadingBuilder`) → warm brown gradient only,
//    no emoji. Reads as "photo about to appear" instead of the
//    old "big emoji then swap to photo" flash that felt like the
//    emoji was the intended visual.
//  • Error (from `errorBuilder`) → warm gradient PLUS the fallback
//    emoji, so a genuinely-dead URL still shows something on-brand
//    instead of a broken-image glyph.
//
//  Frame-in: the image also animates in with a short fade the first
//  time it decodes, so cached vs first-load both feel smooth.
// ───────────────────────────────────────────────────────────────
class _SlideMedia extends StatelessWidget {
  final _Slide slide;
  const _SlideMedia({required this.slide});

  Widget _placeholder({required bool showEmoji}) => Container(
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF2E1D12), CH.char],
          ),
        ),
        child: showEmoji
            ? Text(slide.fallbackEmoji, style: const TextStyle(fontSize: 140))
            : null,
      );

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      Image.network(
        slide.imageUrl,
        fit: BoxFit.cover,
        // Fade the JPEG in over 200 ms once bytes are decoded — kills
        // the hard swap-in flash that made the emoji placeholder feel
        // like a first-class visual.
        frameBuilder: (_, child, frame, wasSyncLoaded) {
          if (wasSyncLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: child,
          );
        },
        // Loading → neutral warm gradient (no emoji). Used to be the
        // huge emoji card which read as the intended design.
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _placeholder(showEmoji: false),
        // Actual load failure → keep the on-brand emoji fallback.
        errorBuilder: (_, __, ___) => _placeholder(showEmoji: true),
      ),
      // Top vignette so the skip pill has contrast against a busy photo.
      const Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end:   Alignment.bottomCenter,
                stops:  [0.0, 0.3],
                colors: [Color(0x66000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ───────────────────────────────────────────────────────────────
//  Skip pill — 44 min hit box, semi-transparent black stadium
// ───────────────────────────────────────────────────────────────
class _SkipPill extends StatelessWidget {
  final VoidCallback onTap;
  const _SkipPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: isArabic ? 'تخطّي' : 'Skip',
      child: SizedBox(
        height: 44,
        child: Material(
          color: Colors.black.withValues(alpha: 0.40),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Center(
                child: Text(
                  isArabic ? 'تخطّي' : 'Skip',
                  style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
