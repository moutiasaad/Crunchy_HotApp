import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../theme/theme.dart';
import '../widgets/ch_phone_field.dart';
import 'app_shell.dart';

/// Screen 03b — Register (إكمال الحساب).
///
/// Shown right after OTP verify when the user's profile is incomplete
/// (fresh signup or missing name/phone). Posts to `POST /profile/complete`
/// via [AuthController.completeProfile]. Same `returnOnSuccess` contract as
/// the login gate — pops with `true` when we came from a guest action.
class RegisterScreen extends StatefulWidget {
  final bool returnOnSuccess;
  const RegisterScreen({super.key, this.returnOnSuccess = false});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _name  = TextEditingController();
  final FocusNode _nameFocus  = FocusNode();
  final FocusNode _phoneFocus = FocusNode();

  /// E.164 form emitted by ChPhoneField (e.g. `+963946193094`).
  String _phoneE164 = '';
  bool   _phoneValid = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _nameFocus.addListener(() => setState(() {}));
    _phoneFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  bool get _nameValid  => _name.text.trim().length >= 2;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_nameValid || !_phoneValid) return;

    final ok = await context.read<AuthController>().completeProfile(
          name:  _name.text.trim(),
          phone: _phoneE164,
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
    final canSubmit = _nameValid && _phoneValid && !auth.sending;
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
                            'خطوة أخيرة عشان تقدر تطلب — منحتاج اسمك ورقم موبايلك.',
                            style: GoogleFonts.cairo(
                              fontSize: 15, height: 1.7, color: CH.muted)),
                          const SizedBox(height: 26),

                          _FieldLabel(text: 'الاسم الكامل'),
                          const SizedBox(height: 8),
                          _NameField(
                            controller: _name,
                            focusNode:  _nameFocus,
                            valid:      _nameValid,
                            onSubmitted: (_) => _phoneFocus.requestFocus(),
                          ),

                          const SizedBox(height: 18),
                          _FieldLabel(text: 'رقم الموبايل'),
                          const SizedBox(height: 8),
                          ChPhoneField(
                            focusNode: _phoneFocus,
                            onChanged: (e164) {
                              context.read<AuthController>().clearError();
                              setState(() {
                                _phoneE164  = e164;
                                _phoneValid = e164.length >= 10;   // + at least 9 local digits
                              });
                            },
                            onSubmitted: (_) => _submit(),
                          ),

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
