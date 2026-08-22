import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../theme/theme.dart';
import '../widgets/ch_phone_field.dart';
import 'app_shell.dart';
import 'otp_screen.dart';

/// Screen 03 — Login (تسجيل الدخول). WhatsApp-OTP first.
///
/// The whole submit/cooldown/error lifecycle lives on [AuthController]
/// (`context.read<AuthController>()`); this widget is a pure view of that
/// state and keeps only UI-local state (focus, phone field controller,
/// animations).
class LoginScreen extends StatefulWidget {
  /// When `true`, this screen was pushed as a **gate** from Cart / Address /
  /// etc. On success the whole Login→OTP flow pops with `true` so the caller
  /// can resume its original action. When `false` (the default), the OTP
  /// screen clears the stack and lands on Home.
  final bool returnOnSuccess;

  const LoginScreen({super.key, this.returnOnSuccess = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final FocusNode _focus = FocusNode();

  /// Current E.164 value emitted by [ChPhoneField]. May be an incomplete
  /// `+963…` prefix while the user is typing.
  String _phone = '';

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  /// E.164: `+` then 8–15 digits (loose upper bound; server also validates).
  static final RegExp _rxPhone = RegExp(r'^\+[1-9]\d{7,14}$');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    _enter.dispose();
    super.dispose();
  }

  bool get _isValid => _rxPhone.hasMatch(_phone);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_isValid) return;

    final auth = context.read<AuthController>();
    final ok = await auth.requestOtp(_phone);
    if (!ok || !mounted) return;

    if (widget.returnOnSuccess) {
      final signed = await Navigator.of(context).push<bool>(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, __, ___) => OtpScreen(
            phone:           auth.pendingPhone!,
            returnOnSuccess: true,
          ),
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        ),
      );
      if (mounted) Navigator.of(context).pop(signed);
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, __, ___) => OtpScreen(phone: auth.pendingPhone!),
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        ),
      );
    }
  }

  void _continueAsGuest() {
    context.read<AuthController>().continueAsGuest();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => const AppShell(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final canSubmit = _isValid && !auth.sending && !auth.onCooldown;

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
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: IgnorePointer(
              ignoring: auth.sending,
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.only(
                  top: 70, start: 26, end: 26, bottom: 36,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EnterFade(
                      controller: _enter, delayMs: 0, reduceMotion: reduceMotion,
                      child: Image.asset('assets/crunchy-hot-logo.jpg',
                        width: 96, filterQuality: FilterQuality.high),
                    ),
                    const SizedBox(height: 22),
                    _EnterFade(
                      controller: _enter, delayMs: 60, reduceMotion: reduceMotion,
                      child: Text('أهلاً بك 👋',
                        style: GoogleFonts.changa(
                          fontSize: 28, fontWeight: FontWeight.w800, color: CH.ink, height: 1.2)),
                    ),
                    const SizedBox(height: 8),
                    _EnterFade(
                      controller: _enter, delayMs: 120, reduceMotion: reduceMotion,
                      child: Text(
                        'سجّل برقم جوالك (واتساب) وبنرسل لك رمز تحقق مؤلف من 6 أرقام.',
                        style: GoogleFonts.cairo(fontSize: 15, height: 1.7, color: CH.muted)),
                    ),
                    const SizedBox(height: 26),
                    Text('رقم الجوال (واتساب)',
                      style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
                    const SizedBox(height: 8),
                    ChPhoneField(
                      initialE164: auth.lastPhone,
                      focusNode:   _focus,
                      errorText:   auth.error,
                      onChanged: (v) {
                        setState(() => _phone = v);
                        context.read<AuthController>().clearError();
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 22),
                    _PrimaryCta(
                      enabled: canSubmit,
                      busy:    auth.sending,
                      cooldownSecs: auth.cooldownSecs,
                      onTap:   _submit,
                    ),
                    if (!widget.returnOnSuccess) ...[
                      const SizedBox(height: 26),
                      const _OrDivider(),
                      const SizedBox(height: 26),
                      _GuestButton(onTap: _continueAsGuest),
                    ],
                    const SizedBox(height: 34),
                    const Center(child: _TermsText()),
                  ],
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
//  Enter animation — fade + slide-up 10 dp, staggered by parent
// ══════════════════════════════════════════════════════════════════
class _EnterFade extends StatelessWidget {
  final AnimationController controller;
  final int    delayMs;
  final Widget child;
  final bool   reduceMotion;

  const _EnterFade({
    required this.controller, required this.delayMs,
    required this.child, required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;
    final start = delayMs / 320.0;
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start.clamp(0.0, 1.0), 1.0, curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - anim.value)),
          child: child,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Primary CTA
// ══════════════════════════════════════════════════════════════════
class _PrimaryCta extends StatefulWidget {
  final bool enabled;
  final bool busy;
  final int  cooldownSecs;
  final VoidCallback onTap;

  const _PrimaryCta({
    required this.enabled, required this.busy,
    required this.cooldownSecs, required this.onTap,
  });

  @override
  State<_PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<_PrimaryCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.cooldownSecs > 0
        ? 'إرسال الرمز  ·  ${widget.cooldownSecs}s'
        : 'إرسال رمز التحقق عبر واتساب';

    return AnimatedScale(
      scale: _pressed && widget.enabled ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: double.infinity,
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
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 17),
              alignment: Alignment.center,
              child: widget.busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(label,
                      style: GoogleFonts.changa(
                        fontSize: 17, fontWeight: FontWeight.w800,
                        color: widget.enabled ? Colors.white : CH.inactive)),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  "أو" divider + Guest button + Terms text
// ══════════════════════════════════════════════════════════════════
class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Expanded(child: Divider(color: CH.line, thickness: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('أو', style: GoogleFonts.cairo(
          fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFC9B6A6))),
      ),
      const Expanded(child: Divider(color: CH.line, thickness: 1)),
    ]);
  }
}

class _GuestButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GuestButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: CH.cream,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('دخول كزائر',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 15, fontWeight: FontWeight.w800, color: CH.muted)),
          ),
        ),
      ),
    );
  }
}

class _TermsText extends StatelessWidget {
  const _TermsText();
  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.cairo(
      fontSize: 12, height: 1.7, color: const Color(0xFFB3A396));
    final link = GoogleFonts.cairo(
      fontSize: 12, height: 1.7, fontWeight: FontWeight.w700, color: CH.hot);
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'بالمتابعة أنت توافق على '),
        TextSpan(text: 'شروط الاستخدام', style: link),
        const TextSpan(text: ' و'),
        TextSpan(text: 'سياسة الخصوصية', style: link),
      ]),
      textAlign: TextAlign.center, style: base,
    );
  }
}
