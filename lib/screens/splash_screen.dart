import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../services/app_prefs.dart';
import '../services/push_notifications_service.dart';
import '../theme/theme.dart';
import 'app_shell.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'register_screen.dart';

/// Screen 01 — Splash (شاشة البداية).
/// Implements every detail from SPLASH_SCREEN.md:
///  - Full-screen white canvas + charcoal bottom arc (top radius 150, scaleX 1.6)
///  - Warm hot glow circle (Ø520, top -90)
///  - Centered logo + tagline column (staggered fade+scale/slide intro)
///  - Loader group pinned 78 from bottom (progress 0→90% in 1200ms easeInOut, then 90→100% in 180ms)
///  - Routes automatically after min 1600ms (max 4000ms) bootstrap
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // 900ms controller drives the staggered logo → tagline → loader-group intro.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Progress controller: 0 → 0.9 over 1200ms, then re-driven 0.9 → 1.0 in 180ms.
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final Animation<double> _progressAnim = Tween<double>(begin: 0, end: 0.9)
      .animate(CurvedAnimation(parent: _progress, curve: Curves.easeInOut));

  bool _bootstrapDone = false;
  bool _bootstrapFailed = false;

  // Slow-state message (shows "جاري التحميل…" after 2.5s)
  bool _slow = false;

  // Hidden dev shortcut: three rapid taps on the logo resets the onboarding
  // flag so the welcome flow shows again on next launch. Useful for testing
  // and demoing without uninstalling the app.
  int _logoTaps = 0;
  DateTime? _lastLogoTap;

  void _onLogoTap() {
    final now = DateTime.now();
    if (_lastLogoTap != null && now.difference(_lastLogoTap!).inSeconds > 1) {
      _logoTaps = 0;
    }
    _lastLogoTap = now;
    _logoTaps++;
    if (_logoTaps >= 3) {
      _logoTaps = 0;
      unawaited(AppPrefs.instance.clearOnboardingSeen());
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('تم إعادة تعيين شاشة الترحيب',
            style: GoogleFonts.cairo(
              fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          backgroundColor: CH.char,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(milliseconds: 1400),
        ));
    }
  }

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _progress.forward();
    _startBootstrap();
  }

  Future<void> _startBootstrap() async {
    final started = DateTime.now();

    // Slow-state timer
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && !_bootstrapDone) setState(() => _slow = true);
    });

    try {
      // Restore session from the stored bearer token (GET /me). Runs in
      // parallel with a 1400 ms floor so the splash animation still gets to
      // play through even on fast networks.
      await Future.wait<void>([
        context.read<AuthController>().bootstrap(),
        Future<void>.delayed(const Duration(milliseconds: 1400)),
      ]);
      _bootstrapDone = true;
    } catch (_) {
      _bootstrapFailed = true;
    }

    final elapsed = DateTime.now().difference(started);
    final wait = const Duration(milliseconds: 1600) - elapsed;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (!mounted) return;

    if (_bootstrapFailed) {
      setState(() {});           // surface the error state
      return;
    }

    // Push progress from wherever it is (usually 0.9) → 1.0 in 180ms, then navigate.
    await _finishProgress();
    if (!mounted) return;

    // Route table:
    //  - onboarding_seen == false                     → OnboardingScreen (02)
    //  - onboarded && no session                       → LoginScreen (03)
    //  - onboarded && session && profile incomplete    → RegisterScreen (03b)
    //  - onboarded && session && profile complete      → HomeScreen (05)
    final auth   = context.read<AuthController>();
    final Widget next;
    if (!AppPrefs.instance.onboardingSeen) {
      next = const OnboardingScreen();
    } else if (!auth.isSignedIn) {
      next = const LoginScreen();
    } else if (auth.needsProfile) {
      next = const RegisterScreen();
    } else {
      // Signed in → make sure the backend has our current FCM token so pushes
      // reach this install. Best-effort; failures are logged, not surfaced.
      unawaited(context.read<PushNotificationsService>().registerCurrentToken());
      next = const AppShell();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _finishProgress() async {
    final from = _progressAnim.value;
    if (from >= 1.0) return;
    _progress
      ..stop()
      ..duration = const Duration(milliseconds: 180);
    // Rebind the Tween so we animate from wherever we are now.
    // Simpler: run a small local animation controller for the sprint.
    final sprint = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    final anim   = Tween<double>(begin: from, end: 1.0)
        .animate(CurvedAnimation(parent: sprint, curve: Curves.easeOut));
    anim.addListener(() {
      // Overlay the sprint value on top of the stalled progress animation
      setState(() {
        _sprintValue = anim.value;
      });
    });
    await sprint.forward();
    sprint.dispose();
  }

  double? _sprintValue;

  double get _visibleProgress => _sprintValue ?? _progressAnim.value;

  @override
  void dispose() {
    _intro.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size    = MediaQuery.sizeOf(context);
    final w       = size.width;
    final h       = size.height;
    final isSmall = w < 360 || h < 640;
    final logoW   = math.min(isSmall ? w * 0.60 : 272.0, w * 0.76);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: CH.char,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Directionality(
            textDirection: TextDirection.ltr,   // symmetric — LTR keeps the arithmetic simple
            child: Stack(
              children: [
                // ---------- 1) warm glow ----------
                Positioned(
                  top: -90,
                  left: (w - 520) / 2,
                  width: 520,
                  height: 520,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          radius: 0.5,
                          stops: [0.0, 0.68],
                          colors: [
                            Color(0x24EE4E1B),   // rgba(238,78,27,.14)
                            Color(0x00EE4E1B),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ---------- 2) bottom arc (charcoal, wide dome) ----------
                Align(
                  alignment: Alignment.bottomCenter,
                  child: IgnorePointer(
                    child: Transform.scale(
                      scaleX: 1.6,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 150,
                        decoration: const BoxDecoration(
                          color: CH.char,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(150),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ---------- 3) center content: logo + tagline ----------
                Center(
                  child: AnimatedBuilder(
                    animation: _intro,
                    builder: (context, child) {
                      // Logo: fade 0→1 + scale 0.92→1 over 0-520ms
                      final logoT = const Interval(0.0, 520 / 900, curve: Curves.easeOutBack)
                          .transform(_intro.value)
                          .clamp(0.0, 1.0);
                      final logoScale = 0.92 + (1.02 - 0.92) * logoT; // gentle overshoot clamp
                      final logoOpacity = logoT.clamp(0.0, 1.0);

                      // Tagline: fade + slide up 8, 260-620ms of the 900ms controller
                      final tagT = const Interval(260 / 900, 620 / 900, curve: Curves.easeOut)
                          .transform(_intro.value);
                      final tagOpacity = tagT.clamp(0.0, 1.0);
                      final tagSlide   = 8 * (1 - tagT);

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label: 'Crunchy Hot',
                            image: true,
                            child: GestureDetector(
                              // Triple-tap re-arms the onboarding flow — see
                              // _onLogoTap above.
                              behavior: HitTestBehavior.opaque,
                              onTap: _onLogoTap,
                              child: Opacity(
                                opacity: logoOpacity,
                                child: Transform.scale(
                                  scale: logoScale.clamp(0.92, 1.02),
                                  child: Image.asset(
                                    'assets/crunchy-hot-logo.jpg',
                                    width: logoW,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: Offset(0, -6 + tagSlide),
                            child: Opacity(
                              opacity: tagOpacity,
                              child: Text(
                                'FAST FOOD',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.changa(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: CH.hot,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Opacity(
                            opacity: tagOpacity,
                            child: Text(
                              'للوجبات السريعة',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.changa(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: CH.hot,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // ---------- 4) loader group (pinned 78 from bottom, or 56 on small screens) ----------
                Positioned(
                  bottom: isSmall ? 56 : 78,
                  left: 0, right: 0,
                  child: AnimatedBuilder(
                    animation: _intro,
                    builder: (context, child) {
                      final loaderT = const Interval(420 / 900, 720 / 900, curve: Curves.easeOut)
                          .transform(_intro.value);
                      return Opacity(opacity: loaderT.clamp(0.0, 1.0), child: child);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Track + fill — wrapped in Directionality.rtl so
                        // the hot fill grows right-to-left, matching how
                        // Arabic readers scan progress. The outer splash
                        // stays LTR for its coordinate arithmetic; only
                        // this widget's direction flips.
                        Directionality(
                          textDirection: TextDirection.rtl,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: SizedBox(
                              width: 132,
                              height: 5,
                              child: AnimatedBuilder(
                                animation: _progress,
                                builder: (context, _) => LinearProgressIndicator(
                                  value: _visibleProgress,
                                  backgroundColor: Colors.white24,
                                  valueColor: AlwaysStoppedAnimation(
                                    _bootstrapFailed ? CH.red : CH.hot,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _CityOrStatusLine(
                          isSlow: _slow,
                          isFailed: _bootstrapFailed,
                        ),
                        if (_bootstrapFailed) ...[
                          const SizedBox(height: 26),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _bootstrapFailed = false;
                                _slow = false;
                                _sprintValue = null;
                              });
                              _progress
                                ..reset()
                                ..forward();
                              _startBootstrap();
                            },
                            child: Text(
                              'إعادة المحاولة',
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: CH.hot,
                              ),
                            ),
                          ),
                        ],
                      ],
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

/// The city label (or a status message when slow / offline).
class _CityOrStatusLine extends StatelessWidget {
  final bool isSlow;
  final bool isFailed;

  const _CityOrStatusLine({required this.isSlow, required this.isFailed});

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch ((isFailed, isSlow)) {
      (true,  _   ) => ('تحقق من اتصالك بالإنترنت',        CH.darkHeaderMuted),
      (false, true) => ('جاري التحميل…',                    CH.darkHeaderMuted),
      _             => ('حلب — سوريا · ALEPPO — SYRIA',    CH.darkHeaderMuted),
    };

    return Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.cairo(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: color,
      ),
    );
  }
}
