import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../theme/theme.dart';
import 'app_shell.dart';

/// Screen 03b — Register (إكمال الحساب).
///
/// Shown right after OTP verify when the user's profile is incomplete
/// (fresh signup with no display name). Phone is already captured + verified
/// during login (WhatsApp OTP), so this screen only asks for the display
/// name plus an optional email for order-status notifications. Posts to
/// `POST /profile/complete` via [AuthController.completeProfile].
class RegisterScreen extends StatefulWidget {
  final bool returnOnSuccess;
  const RegisterScreen({super.key, this.returnOnSuccess = false});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _name  = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final FocusNode _nameFocus  = FocusNode();
  final FocusNode _emailFocus = FocusNode();

  static final RegExp _rxEmail = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _email.addListener(() => setState(() {}));
    _nameFocus.addListener(() => setState(() {}));
    _emailFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  bool get _nameValid  => _name.text.trim().length >= 2;
  /// Email is optional. When present it must parse; when empty it's fine.
  bool get _emailValid {
    final t = _email.text.trim();
    return t.isEmpty || _rxEmail.hasMatch(t);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_nameValid || !_emailValid) return;

    final emailTrim = _email.text.trim();
    final ok = await context.read<AuthController>().completeProfile(
          name:  _name.text.trim(),
          email: emailTrim.isEmpty ? null : emailTrim,
        );
    if (!ok || !mounted) return;

    if (widget.returnOnSuccess) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (_, __, ___) => const AppShell(),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
        ),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canSubmit = _nameValid && _emailValid && !auth.sending;
    final topInset = MediaQuery.paddingOf(context).top;

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
          body: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: IgnorePointer(
                    ignoring: auth.sending,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        top: topInset + 40, start: 26, end: 26, bottom: 36,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('أكمل بياناتك 👋',
                            style: GoogleFonts.changa(
                              fontSize: 28, fontWeight: FontWeight.w800,
                              color: CH.ink, height: 1.2)),
                          const SizedBox(height: 8),
                          Text(
                            'اسمك بيظهر مع طلباتك — رقم جوالك محفوظ من عملية الدخول.',
                            style: GoogleFonts.cairo(
                              fontSize: 15, height: 1.7, color: CH.muted)),
                          const SizedBox(height: 26),

                          const _FieldLabel(text: 'الاسم الكامل'),
                          const SizedBox(height: 8),
                          _NameField(
                            controller: _name,
                            focusNode:  _nameFocus,
                            valid:      _nameValid,
                            onSubmitted: (_) => _emailFocus.requestFocus(),
                          ),

                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const _FieldLabel(text: 'البريد الإلكتروني'),
                              const SizedBox(width: 6),
                              Text('(اختياري)',
                                style: GoogleFonts.cairo(
                                  fontSize: 12, color: CH.muted)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _EmailField(
                            controller:  _email,
                            focusNode:   _emailFocus,
                            valid:       _email.text.trim().isNotEmpty && _emailValid,
                            hasError:    _email.text.trim().isNotEmpty && !_emailValid && !_emailFocus.hasFocus,
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 6),
                          Text('لاستلام إشعارات الطلب بالإيميل — يمكنك تركه فارغاً.',
                            style: GoogleFonts.cairo(
                              fontSize: 12, color: CH.muted)),

                          if (auth.error != null) ...[
                            const SizedBox(height: 10),
                            Semantics(
                              liveRegion: true,
                              child: Text(auth.error!,
                                style: GoogleFonts.cairo(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: CH.red)),
                            ),
                          ],

                          const SizedBox(height: 22),
                          _PrimaryCta(
                            enabled: canSubmit,
                            busy:    auth.sending,
                            onTap:   _submit,
                          ),

                          const Spacer(),
                          Center(
                            child: Text(
                              'بياناتك محفوظة عندنا فقط ولن تشارك.',
                              style: GoogleFonts.cairo(
                                fontSize: 12, color: CH.muted),
                            ),
                          ),
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
}

// ══════════════════════════════════════════════════════════════════
//  Small pieces
// ══════════════════════════════════════════════════════════════════
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel({required this.text});
  @override
  Widget build(BuildContext context) => Text(text,
        style: GoogleFonts.cairo(
          fontSize: 13, fontWeight: FontWeight.w800, color: CH.muted),
      );
}

class _NameField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool valid;
  final ValueChanged<String>? onSubmitted;
  const _NameField({
    required this.controller, required this.focusNode,
    required this.valid, this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: focused ? const Color(0xFFFFF7F2) : CH.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (focused || valid) ? CH.hot : CH.line,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: CH.muted),
          const SizedBox(width: 10),
          Container(width: 1, height: 22, color: CH.line),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(120)],
              onSubmitted: onSubmitted,
              cursorColor: CH.hot,
              style: GoogleFonts.cairo(
                fontSize: 16, fontWeight: FontWeight.w700, color: CH.ink),
              decoration: InputDecoration(
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
                hintText: 'اكتب اسمك الكامل',
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
    );
  }
}

class _EmailField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool valid;
  final bool hasError;
  final ValueChanged<String>? onSubmitted;
  const _EmailField({
    required this.controller, required this.focusNode,
    required this.valid, required this.hasError, this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final focused = focusNode.hasFocus;
    final borderColor = hasError
        ? CH.red
        : (focused || valid) ? CH.hot : CH.line;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: focused ? const Color(0xFFFFF7F2) : CH.cream,
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
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  LengthLimitingTextInputFormatter(255),
                ],
                onSubmitted: onSubmitted,
                cursorColor: CH.hot,
                style: GoogleFonts.cairo(
                  fontSize: 16, fontWeight: FontWeight.w700, color: CH.ink),
                decoration: InputDecoration(
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
                  hintText: 'example@gmail.com',
                  hintTextDirection: TextDirection.ltr,
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

class _PrimaryCta extends StatefulWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  const _PrimaryCta({
    required this.enabled, required this.busy, required this.onTap,
  });

  @override
  State<_PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<_PrimaryCta> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
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
                  : Text('تابع',
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
