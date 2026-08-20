import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Cream2 image placeholder — used everywhere product photos are missing.
/// Follows the spec: image placeholder fill with `cream2`.
class ChImagePlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final String? emoji;

  const ChImagePlaceholder({
    super.key,
    this.width,
    this.height,
    this.borderRadius = ChRadii.rLg,
    this.emoji = '🍗',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: CH.cream2,
        borderRadius: borderRadius,
      ),
      alignment: Alignment.center,
      child: Text(
        emoji ?? '🍗',
        style: TextStyle(
          fontSize: (width != null && height != null)
              ? (width! < height! ? width! : height!) * 0.45
              : 40,
        ),
      ),
    );
  }
}
