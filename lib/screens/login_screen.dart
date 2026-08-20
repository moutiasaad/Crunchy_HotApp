import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../theme/theme.dart';
import 'app_shell.dart';
import 'otp_screen.dart';

/// Screen 03 — Login (تسجيل الدخول). Email-first, MVCS-wired.
///
/// The whole submit/cooldown/error lifecycle lives on [AuthController]
/// (`context.read<AuthController>()`); this widget is a pure view of that
/// state and keeps only UI-local state (focus, text controller, animations).
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
  final TextEditingController _email = TextEditingController();
  final FocusNode              _focus = FocusNode();

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  static final RegExp _rxEmail = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  @override
  void initState() {
    super.initState();
    // Do NOT pre-fill from AuthController.lastEmail — the field opens blank
    // every time so a returning user always types (or dictates) their address
    // deliberately. Auto-fill via the platform keyboard's password manager
    // still works.
    _email.addListener(() {
      context.read<AuthController>().clearError();
      setState(() {});
    });
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _focus.dispose();
    _enter.dispose();
    super.dispose();
  }

  bool get _isValid => _rxEmail.hasMatch(_email.text.trim());

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_isValid) return;

    final auth = context.read<AuthController>();
    final ok = await auth.requestOtp(_email.text.trim().toLowerCase());
    if (!ok || !mounted) return;

    if (widget.returnOnSuccess) {
      // Modal-gate mode: push (not pushReplacement) so we can pop through
      // both Login and OTP back to the caller with a single bool result.
      final signed = await Navigator.of(context).push<bool>(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, __, ___) => OtpScreen(
            email:           auth.pendingEmail!,
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
          pageBuilder: (_, __, ___) => OtpScreen(email: auth.pendingEmail!),
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

    final String? shownError = (!_isValid && _email.text.isNotEmpty && !_focus.hasFocus)
        ? 'بريد إلكتروني غير صحيح — تأكد من الصياغة'
        : auth.error;

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
                        'سجّل ببريدك الإلكتروني وبنرسل لك رمز تحقق مؤلف من 6 أرقام.',
                        style: GoogleFonts.cairo(fontSize: 15, height: 1.7, color: CH.muted)),
                    ),
                    const SizedBox(height: 26),
                    Text('البريد الإلكتروني',
                      style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted)),
                    const SizedBox(height: 8),
                    _EmailField(
                      controller: _email,
                      focusNode:  _focus,
                      error:      shownError != null,
                      valid:      _isValid,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (shownError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(shownError,
                            style: GoogleFonts.cairo(
                              fontSize: 12, fontWeight: FontWeight.w700, color: CH.red)),
                        ),
                      ),
                    const SizedBox(height: 22),
                    _PrimaryCta(
                      enabled: canSubmit,
                      busy:    auth.sending,
                      cooldownSecs: auth.cooldownSecs,
                      onTap:   _submit,
                    ),
                    // Guest escape hatch is hidden in modal-gate mode —
                    // the whole point of pushing Login was to require sign-in.
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
//  Email field
// ══════════════════════════════════════════════════════════════════
class _EmailField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool error;
  final bool valid;
  final ValueChanged<String>? onSubmitted;

  const _EmailField({
    required this.controller, required this.focusNode,
    this.error = false, this.valid = false, this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    final Color borderColor = error
        ? CH.red
        : (focused || valid) ? CH.hot : CH.line;
    final Color fill = focused ? const Color(0xFFFFF7F2) : CH.cream;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.mail_outline_rounded, size: 18, color: CH.muted),
            const SizedBox(width: 10),
            Container(width: 1, height: 22, color: CH.line),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  LengthLimitingTextInputFormatter(255),
                ],
                style: GoogleFonts.cairo(
                  fontSize: 16, fontWeight: FontWeight.w700, color: CH.ink),
                cursorColor: CH.hot,
                onSubmitted: onSubmitted,
                decoration: InputDecoration(
                  // Kill EVERY border variant — the app-wide inputDecorationTheme
                  // sets an OutlineInputBorder on enabled/focused/error, so
                  // overriding only `border` leaves a stray rectangle behind.
                  border:            InputBorder.none,
                  enabledBorder:     InputBorder.none,
                  focusedBorder:     InputBorder.none,
                  errorBorder:       InputBorder.none,
                  focusedErrorBorder:InputBorder.none,
                  disabledBorder:    InputBorder.none,
                  filled:            false,
                  fillColor:         Colors.transparent,
                  isDense:           true,
                  contentPadding:    EdgeInsets.zero,
                  hintText: 'اكتب بريدك الإلكتروني',
                  // Hint reads RTL even though the field body stays LTR (so
                  // a real email address types left-to-right).
                  hintTextDirection: TextDirection.rtl,
                  hintStyle: GoogleFonts.cairo(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: const Color(0xFFB3A396)),
                ),
              ),
            ),
            if (valid) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle_rounded, color: CH.green, size: 20),
            ],
          ],
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
        : 'إرسال رمز التحقق';

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
