import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 5-star rating, 32px, yellow when filled / #E6D6C6 empty.
class ChRating extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  const ChRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < value;
        return GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(
              Icons.star_rounded,
              size: size,
              color: filled ? CH.yellow : CH.timelineIdle,
            ),
          ),
        );
      }),
    );
  }
}
