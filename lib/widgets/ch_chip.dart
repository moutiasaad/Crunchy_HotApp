import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Stadium-shaped category / filter chip.
/// Selected: hot fill, white text, soft glow.
/// Unselected: white fill, 1.5 line border, ink text.
class ChChip extends StatelessWidget {
  final String label;
  final String? emoji;
  final bool selected;
  final VoidCallback? onTap;

  const ChChip({
    super.key,
    required this.label,
    this.emoji,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg   = selected ? CH.hot   : CH.paper;
    final fg   = selected ? CH.paper : CH.ink;

    return Container(
      decoration: BoxDecoration(
        borderRadius: ChRadii.rStadium,
        boxShadow: selected ? ChShadows.chipSelected : null,
      ),
      child: Material(
        color: bg,
        borderRadius: ChRadii.rStadium,
        child: InkWell(
          borderRadius: ChRadii.rStadium,
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: ChRadii.rStadium,
              border: selected
                  ? null
                  : Border.all(color: CH.line, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (emoji != null) ...[
                  Text(emoji!, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: ChText.label.copyWith(color: fg, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
