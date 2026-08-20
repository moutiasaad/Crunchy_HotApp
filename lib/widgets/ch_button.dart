import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Primary button — full-width, hot fill, orange glow shadow.
/// Often shows a trailing value: `تأكيد الطلب · 91,000 ل.س`.
class ChPrimaryButton extends StatelessWidget {
  final String label;
  final String? trailingValue;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;

  const ChPrimaryButton({
    super.key,
    required this.label,
    this.trailingValue,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    return Container(
      width: expanded ? double.infinity : null,
      decoration: BoxDecoration(
        borderRadius: ChRadii.rXl,
        boxShadow: disabled ? null : ChShadows.primaryButton,
      ),
      child: Material(
        color: disabled ? CH.line : CH.hot,
        borderRadius: ChRadii.rXl,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: ChRadii.rXl,
          splashColor: CH.hotDeep.withValues(alpha: 0.35),
          highlightColor: CH.hotDeep.withValues(alpha: 0.20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(CH.paper),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (icon != null) ...[
                  Icon(icon, color: CH.paper, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: ChText.button.copyWith(
                    color: disabled ? CH.inactive : CH.paper,
                  ),
                ),
                if (trailingValue != null) ...[
                  const SizedBox(width: 8),
                  Text('·', style: ChText.button.copyWith(color: disabled ? CH.inactive : CH.paper)),
                  const SizedBox(width: 8),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      trailingValue!,
                      style: ChText.button.copyWith(color: disabled ? CH.inactive : CH.paper),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary / dark button — `char` fill, white Cairo 800.
/// Used for square `+` add buttons on cards, and for "أضف العرض للسلة".
class ChDarkButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;

  const ChDarkButton({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.padding,
    this.borderRadius = ChRadii.rLg,
  });

  /// Small square `+` button (40×40, used on featured / list cards).
  const ChDarkButton.plus({
    super.key,
    required VoidCallback this.onPressed,
  })  : label = null,
        icon = Icons.add,
        padding = EdgeInsets.zero,
        borderRadius = ChRadii.rSm;

  @override
  Widget build(BuildContext context) {
    final isSquare = label == null;
    return Material(
      color: CH.char,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: borderRadius,
        child: SizedBox(
          width: isSquare ? 40 : null,
          height: isSquare ? 40 : null,
          child: Padding(
            padding: padding ??
                (isSquare
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) Icon(icon, color: CH.paper, size: isSquare ? 22 : 18),
                if (icon != null && label != null) const SizedBox(width: 8),
                if (label != null)
                  Text(
                    label!,
                    style: ChText.bodyStrong.copyWith(color: CH.paper),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ghost / outline button — white fill, line border, ink text.
class ChGhostButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expanded;

  const ChGhostButton({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CH.paper,
      borderRadius: ChRadii.rMd,
      child: InkWell(
        onTap: onPressed,
        borderRadius: ChRadii.rMd,
        child: Container(
          width: expanded ? double.infinity : null,
          decoration: BoxDecoration(
            borderRadius: ChRadii.rMd,
            border: Border.all(color: CH.line, width: 1.5),
          ),
          padding: label == null
              ? const EdgeInsets.all(10)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, color: CH.ink, size: 20),
              if (icon != null && label != null) const SizedBox(width: 8),
              if (label != null)
                Text(label!, style: ChText.bodyStrong),
            ],
          ),
        ),
      ),
    );
  }
}
