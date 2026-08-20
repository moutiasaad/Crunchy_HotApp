import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../services/push_notifications_service.dart';
import '../theme/theme.dart';
import 'app_shell.dart';
import 'register_screen.dart';

/// Screen 04 — OTP verification (كود التحقق).
///
/// Implements every detail from OTP_SCREEN.md:
///  - White canvas, dark status icons, portrait-locked.
///  - Padding 70 / 26 / 36 + safe area, keyboard auto-opens.
///  - Back button (40×40, radius 12, glyph → in RTL / ← in LTR).
///  - Title "كود التحقق" Changa 800 28, body Cairo 400 15 muted + phone in Cairo 800 ink (LTR).
///  - Row of 4 boxes, always LTR, aspect 1:1, radius 16.
///  - States: filled / active / empty / error / verifying — colors + borders per spec.
///  - Auto-submit on 4th digit; single hidden TextField drives painted boxes.
///  - `AutofillHints.oneTimeCode` + `TextInputType.number` for SMS Retriever.
///  - Countdown 60 s → resend button in `hot`.
///  - Error: shake ±6 dp / 300 ms + haptic + attempts-left messaging + auto-clear + refocus.
///  - Lock after 5 failures.
///  - Success: green border flash + fade-through 240 ms to Home.
///  - Security note pinned to the bottom (cream box, 🔒 + reassurance line).
class OtpScreen extends StatefulWidget {
  /// The email the user typed on Login. Backend delivers the 6-digit code here.
  final String email;

  /// See [LoginScreen.returnOnSuccess] — when `true`, verify success pops
  /// back to the caller with `true` instead of rebuilding the stack on Home.
  final bool returnOnSuccess;

  const OtpScreen({
    super.key,
    required this.email,
    this.returnOnSuccess = false,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with TickerProviderStateMixin {
  // 6-digit email OTP (matches the Laravel backend). Change to 4 if you ever
  // switch to an SMS provider that ships shorter codes.
  static const int _len = 6;

  final TextEditingController _code  = TextEditingController();
  final FocusNode              _focus = FocusNode();

  int  _left      = 60;      // resend countdown seconds
  int  _attempts  = 0;       // failed verification attempts
  bool _busy      = false;
  bool _success   = false;
  String? _error;
  Timer? _tick;

  // 300 ms fade + boxes scale-in intro
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  // 300 ms horizontal shake on error
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  bool get _isLocked => _attempts >= 5;
  bool get _isValid  => _code.text.length == _len && !_isLocked;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _code.addListener(_onChanged);
    // Auto-open the keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    _focus.dispose();
    _enter.dispose();
    _shake.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  //  Countdown
  // ---------------------------------------------------------------
  void _startCountdown() {
    _tick?.cancel();
    setState(() => _left = 60);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_left <= 1) {
        setState(() => _left = 0);
        t.cancel();
      } else {
        setState(() => _left--);
      }
    });
  }

  String get _clock =>
      '${(_left ~/ 60).toString().padLeft(2, '0')}:${(_left % 60).toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------
  //  Input handling
  // ---------------------------------------------------------------
  void _onChanged() {
    if (_error != null) setState(() => _error = null);
    setState(() {});
    if (_code.text.length == _len && !_busy && !_isLocked) {
      _verify();
    }
  }

  /// Convert Arabic-Indic digits (٠-٩) to ASCII 0-9 so the code round-trips
  /// through Laravel's `size:6` validator regardless of the user's keyboard.
  static String _normalizeDigits(String s) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final buf = StringBuffer();
    for (final ch in s.characters) {
      final idx = arabic.indexOf(ch);
      buf.write(idx >= 0 ? idx.toString() : ch);
    }
    return buf.toString();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });

    final raw  = _code.text;
    final norm = _normalizeDigits(raw);

    if (kDebugMode) {
      final rawHex = raw.codeUnits
          .map((c) => c.toRadixString(16).padLeft(4, '0'))
          .join(' ');
      debugPrint(
        '[OTP] typed → raw="$raw"  len=${raw.length}  chars=[$rawHex]',
      );
      debugPrint(
        '[OTP] normalized → "$norm"  len=${norm.length}  ${raw == norm ? "(same)" : "(digits converted)"}',
      );
      debugPrint('[OTP] pending email = "${widget.email}"  attempt #${_attempts + 1}');
    }

    final auth = context.read<AuthController>();
    final ok = await auth.verifyOtp(norm);

    if (!mounted) return;

    if (ok) {
      HapticFeedback.lightImpact();
      setState(() => _success = true);

      // Register the current FCM token with the backend now that we have a
      // Sanctum session — fire-and-forget so the "success → route" chain
      // isn't blocked by a slow /devices call.
      unawaited(context.read<PushNotificationsService>().registerCurrentToken());

      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;

      // New account (or existing user with no name/phone yet) → detour
      // through Register before landing on Home or returning to the caller.
      final needsProfile = auth.needsProfile;

      if (needsProfile) {
        if (widget.returnOnSuccess) {
          // Modal-gate mode: propagate the Register result up the stack.
          final result = await Navigator.of(context).push<bool>(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 240),
              pageBuilder: (_, __, ___) =>
                  const RegisterScreen(returnOnSuccess: true),
              transitionsBuilder: (_, a, __, child) =>
                  FadeTransition(opacity: a, child: child),
            ),
          );
          if (mounted) Navigator.of(context).pop(result);
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 240),
              pageBuilder: (_, __, ___) => const RegisterScreen(),
              transitionsBuilder: (_, a, __, child) =>
                  FadeTransition(opacity: a, child: child),
            ),
            (_) => false,
          );
        }
      } else if (widget.returnOnSuccess) {
        // Modal-gate mode: hand control back to the caller through Login.
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 240),
            pageBuilder: (_, __, ___) => const AppShell(),
            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
          ),
          (_) => false,
        );
      }
    } else {
      _attempts++;
      HapticFeedback.mediumImpact();
      _shake.forward(from: 0);
      setState(() {
        _code.clear();
        _busy = false;
        _error = _isLocked
            ? 'تم إيقاف المحاولات مؤقتاً — جرّب بعد 5 دقايق'
            : (_attempts >= 3
                ? 'الكود غير صحيح — باقي ${5 - _attempts} محاولات'
                : (auth.error ?? 'الكود غير صحيح — جرّب مرة تانية'));
      });
      auth.clearError();
      _focus.requestFocus();
    }
  }

  Future<void> _resend() async {
    if (_left > 0 || _busy || _isLocked) return;
    _code.clear();
    setState(() => _error = null);

    final auth = context.read<AuthController>();
    final ok = await auth.requestOtp(widget.email);
    if (!ok) return;
    _startCountdown();
  }

  // ---------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

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
            // Wrap in a scroll view so the keyboard can push the content up
            // without triggering "RenderFlex overflowed by N pixels on the
            // bottom" on shorter phones. The min-height + IntrinsicHeight
            // pattern keeps the `Spacer` working when there's room to spare.
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: 70, start: 26, end: 26, bottom: 36,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  // ---------- Back button (40×40) ----------
                  _BackButton(
                    glyph: isArabic ? '→' : '←',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 24),

                  // ---------- Title ----------
                  Text(
                    'كود التحقق',
                    style: GoogleFonts.changa(
                      fontSize: 28, fontWeight: FontWeight.w800, color: CH.ink, height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ---------- Body (with LTR email) ----------
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'أرسلنا رمز مؤلف من 6 أرقام إلى ',
                          style: GoogleFonts.cairo(fontSize: 15, height: 1.7, color: CH.muted),
                        ),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              widget.email,
                              style: GoogleFonts.cairo(
                                fontSize: 15, fontWeight: FontWeight.w800, color: CH.ink, height: 1.7,
                              ),
                            ),
                          ),
                        ),
                        TextSpan(
                          text: ' — تحقّق من صندوق الوارد و"البريد المزعج".',
                          style: GoogleFonts.cairo(fontSize: 15, height: 1.7, color: CH.muted),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ---------- 4 boxes + hidden TextField ----------
                  _OtpBoxes(
                    controller: _code,
                    focusNode: _focus,
                    length: _len,
                    busy: _busy,
                    error: _error != null,
                    success: _success,
                    shake: _shake,
                    enter: _enter,
                    reduceMotion: reduceMotion,
                    locked: _isLocked,
                  ),

                  // ---------- Error line ----------
                  if (_error != null && !_isLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: GoogleFonts.cairo(
                            fontSize: 12, fontWeight: FontWeight.w700, color: CH.red,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // ---------- Resend / countdown ----------
                  if (!_isLocked)
                    _left > 0
                        ? Text(
                            // Arabic reads right-to-left; the `_clock` digits
                            // (e.g. 00:59) render as an LTR run inside the RTL
                            // paragraph automatically per Unicode bidi. Don't
                            // wrap in `Directionality.ltr` — that would flip
                            // the Arabic phrase's visual order.
                            _isArabicResend(isArabic)
                                ? 'إعادة إرسال الكود بعد $_clock'
                                : 'Resend code in $_clock',
                            style: GoogleFonts.cairo(
                              fontSize: 14, fontWeight: FontWeight.w700, color: CH.muted,
                            ),
                          )
                        : TextButton(
                            onPressed: _resend,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 44),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'إعادة إرسال الكود',
                              style: GoogleFonts.cairo(
                                fontSize: 14, fontWeight: FontWeight.w800, color: CH.hot,
                              ),
                            ),
                          ),

                  const SizedBox(height: 26),

                  // ---------- Primary CTA ----------
                  if (!_isLocked)
                    _VerifyCta(
                      enabled: _isValid && !_busy,
                      busy: _busy,
                      onTap: _verify,
                    ),

                  const Spacer(),

                  // ---------- Security note ----------
                  _SecurityNote(locked: _isLocked),
                        ],
                      ),
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

  bool _isArabicResend(bool isArabic) => isArabic; // kept as a hook if we later localize
}

// ══════════════════════════════════════════════════════════════════
//  Back button (40×40, white fill, 1.5 line border, radius 12)
// ══════════════════════════════════════════════════════════════════
class _BackButton extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  const _BackButton({required this.glyph, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'رجوع',
      child: SizedBox(
        width: 40, height: 40,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CH.line, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                glyph,
                style: GoogleFonts.cairo(
                  fontSize: 17, fontWeight: FontWeight.w800, color: CH.ink,
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
//  4 painted boxes driven by a single hidden TextField
// ══════════════════════════════════════════════════════════════════
class _OtpBoxes extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool busy;
  final bool error;
  final bool success;
  final bool locked;
  final AnimationController shake;
  final AnimationController enter;
  final bool reduceMotion;

  const _OtpBoxes({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.busy,
    required this.error,
    required this.success,
    required this.locked,
    required this.shake,
    required this.enter,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: 'كود التحقق',
      value: controller.text,
      child: AnimatedBuilder(
        animation: Listenable.merge([controller, shake, enter]),
        builder: (context, _) {
          // Shake: ±6 dp using a triangle wave
          final shakeDx = reduceMotion
              ? 0.0
              : (6 * _triangleWave(shake.value) * (1 - shake.value)).toDouble();
          // Enter scale: 0.96 → 1
          final scale = reduceMotion ? 1.0 : (0.96 + 0.04 * enter.value);

          return Transform.translate(
            offset: Offset(shakeDx, 0),
            child: Transform.scale(
              scale: scale,
              child: Stack(
                children: [
                  Opacity(
                    opacity: enter.value.clamp(0.0, 1.0),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        children: [
                          for (int i = 0; i < length; i++) ...[
                            Expanded(
                              child: _OtpBox(
                                state: _boxStateFor(
                                  filled:  i < controller.text.length,
                                  active:  i == controller.text.length,
                                  hasError: error,
                                  success:  success,
                                  busy:     busy,
                                  locked:   locked,
                                ),
                                digit: i < controller.text.length ? controller.text[i] : '',
                              ),
                            ),
                            if (i != length - 1) const SizedBox(width: 12),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Invisible TextField for input capture
                  Positioned.fill(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: GestureDetector(
                        onTap: locked ? null : focusNode.requestFocus,
                        behavior: HitTestBehavior.opaque,
                        child: Opacity(
                          opacity: 0.0,
                          child: IgnorePointer(
                            ignoring: false,
                            child: TextField(
                              controller: controller,
                              focusNode: focusNode,
                              autofocus: true,
                              enabled: !locked,
                              readOnly: busy,
                              keyboardType: TextInputType.number,
                              maxLength: length,
                              showCursor: false,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              inputFormatters: [
                                // Accept BOTH ASCII 0-9 AND Arabic-Indic ٠-٩ so
                                // an Arabic numeric keypad doesn't silently
                                // strip every digit. Normalization happens in
                                // _normalizeDigits() before we call the API.
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9٠-٩]'),
                                ),
                                LengthLimitingTextInputFormatter(length),
                              ],
                              style: const TextStyle(color: Colors.transparent, height: 1),
                              decoration: const InputDecoration(
                                counterText: '',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static _BoxState _boxStateFor({
    required bool filled,
    required bool active,
    required bool hasError,
    required bool success,
    required bool busy,
    required bool locked,
  }) {
    if (locked)   return _BoxState.locked;
    if (success)  return _BoxState.success;
    if (hasError) return _BoxState.error;
    if (busy)     return _BoxState.verifying;
    if (filled)   return _BoxState.filled;
    if (active)   return _BoxState.active;
    return _BoxState.empty;
  }

  /// Triangle wave for a shake animation (goes 0 → 1 → -1 → 1 → -1 → 0).
  static double _triangleWave(double t) {
    // Simple approach: two full oscillations across [0, 1]
    return (t <= 0 || t >= 1)
        ? 0
        : (1 - 2 * ((t * 4).floor() % 2 == 0 ? (t * 4) % 1 : 1 - (t * 4) % 1));
  }
}

enum _BoxState { empty, active, filled, error, verifying, success, locked }

class _OtpBox extends StatelessWidget {
  final _BoxState state;
  final String digit;
  const _OtpBox({required this.state, required this.digit});

  @override
  Widget build(BuildContext context) {
    // Border width kept at 2 for active/error/success so those states pop
    // against the 1.5-line resting borders elsewhere in the app; empty is
    // 1.5 so the resting row reads as calm.
    final ({Color border, double borderWidth, Color fill, Widget content}) style;
    switch (state) {
      case _BoxState.empty:
        // No glyph — an empty box should read as empty, not as a field with
        // a cursor. The old `|` in every box made all 6 look active.
        style = (border: CH.line, borderWidth: 1.5, fill: Colors.white,
          content: const SizedBox.shrink());
        break;
      case _BoxState.active:
        // Just the border + a thin blinking caret. No peach fill — the fill
        // combined with the fat Changa `|` made this state look like a solid
        // orange blob at small sizes.
        style = (border: CH.hot, borderWidth: 2, fill: Colors.white,
          content: const _BlinkingCaret());
        break;
      case _BoxState.filled:
        style = (border: CH.hot, borderWidth: 2, fill: Colors.white,
          content: Text(digit, style: GoogleFonts.changa(
            fontSize: 28, fontWeight: FontWeight.w800, color: CH.ink)));
        break;
      case _BoxState.error:
        style = (border: CH.red, borderWidth: 2, fill: const Color(0xFFFFF4F4),
          content: Text(digit, style: GoogleFonts.changa(
            fontSize: 28, fontWeight: FontWeight.w800, color: CH.red)));
        break;
      case _BoxState.verifying:
        style = (border: CH.hot.withValues(alpha: 0.40), borderWidth: 2, fill: Colors.white,
          content: Text(digit, style: GoogleFonts.changa(
            fontSize: 28, fontWeight: FontWeight.w800, color: CH.ink.withValues(alpha: 0.55))));
        break;
      case _BoxState.success:
        style = (border: CH.green, borderWidth: 2, fill: const Color(0xFFF1FBF3),
          content: Text(digit, style: GoogleFonts.changa(
            fontSize: 28, fontWeight: FontWeight.w800, color: CH.ink)));
        break;
      case _BoxState.locked:
        style = (border: CH.line, borderWidth: 1.5, fill: CH.cream,
          content: const SizedBox.shrink());
        break;
    }

    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: style.fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: style.border, width: style.borderWidth),
        ),
        alignment: Alignment.center,
        child: style.content,
      ),
    );
  }
}

/// Thin 2×22 blinking bar — matches how a native TextField caret reads,
/// instead of the previous fat Changa `|` glyph.
class _BlinkingCaret extends StatefulWidget {
  const _BlinkingCaret();

  @override
  State<_BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<_BlinkingCaret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.2, end: 1).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 2, height: 22,
        decoration: BoxDecoration(
          color: CH.hot,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Verify CTA — hot, radius 16, disabled until 4 digits
// ══════════════════════════════════════════════════════════════════
class _VerifyCta extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _VerifyCta({required this.enabled, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled ? ChShadows.primaryButton : null,
        ),
        child: Material(
          color: enabled ? CH.hot : CH.line,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(16),
            splashColor: CH.hotDeep.withValues(alpha: 0.30),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 17),
              alignment: Alignment.center,
              child: busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      'تحقّق ومتابعة',
                      style: GoogleFonts.changa(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: enabled ? Colors.white : CH.inactive,
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
//  Security note — cream box, 🔒 + reassurance line
// ══════════════════════════════════════════════════════════════════
class _SecurityNote extends StatelessWidget {
  final bool locked;
  const _SecurityNote({required this.locked});

  @override
  Widget build(BuildContext context) {
    final text = locked
        ? 'تم إيقاف المحاولات مؤقتاً — جرّب بعد 5 دقايق.'
        : 'ما نطلب منك كلمة سر — الدخول بكود لمرة واحدة فقط.';
    final bg = locked ? const Color(0x14E11D2A) : CH.cream;   // rgba(225,29,42,.08) tint when locked
    final textColor = locked ? CH.red : const Color(0xFF6D5D51);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Text('🔒', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.cairo(
                fontSize: 13, height: 1.6, color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
