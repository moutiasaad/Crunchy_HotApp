import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/theme.dart';

/// Modal bottom sheet that gates a guest action behind sign-in.
///
/// Returns `true` if the user tapped "تسجيل الدخول", `false` if they
/// dismissed or hit "إلغاء". Never returns `null` (dismissal counts as
/// cancel).
Future<bool> showSignInPromptSheet(
  BuildContext context, {
  required String title,
  required String body,
  String primaryLabel = 'تسجيل الدخول',
  String cancelLabel  = 'إلغاء',
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (sheetCtx) => _SignInPromptSheet(
      title:        title,
      body:         body,
      primaryLabel: primaryLabel,
      cancelLabel:  cancelLabel,
    ),
  );
  return r == true;
}

class _SignInPromptSheet extends StatelessWidget {
  final String title;
  final String body;
  final String primaryLabel;
  final String cancelLabel;
  const _SignInPromptSheet({
    required this.title, required this.body,
    required this.primaryLabel, required this.cancelLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: 20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: CH.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          const Text('🔒',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(title,
            textAlign: TextAlign.center,
            style: GoogleFonts.changa(
              fontSize: 20, fontWeight: FontWeight.w800, color: CH.ink)),
          const SizedBox(height: 8),
          Text(body,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 14, height: 1.6, color: CH.muted)),
          const SizedBox(height: 22),
          _PrimaryBtn(
            label: primaryLabel,
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(cancelLabel,
              style: GoogleFonts.cairo(
                fontSize: 14, fontWeight: FontWeight.w800, color: CH.muted)),
          ),
        ],
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: ChShadows.primaryButton,
      ),
      child: Material(
        color: CH.hot,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: CH.hotDeep.withValues(alpha: 0.30),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Center(
              child: Text(label,
                style: GoogleFonts.changa(
                  fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}
