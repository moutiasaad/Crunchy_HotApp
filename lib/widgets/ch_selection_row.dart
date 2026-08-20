import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Selection row (address / branch / payment).
/// White, radius 18, padding 14. Leading 42 square radius 12 `cream` tile.
/// Trailing 20 radio with 2px border. Selected → 1.5 hot border on the row.
class ChSelectionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String emoji;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  const ChSelectionRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.emoji,
    this.selected = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CH.paper,
      borderRadius: ChRadii.rCard,
      child: InkWell(
        onTap: onTap,
        borderRadius: ChRadii.rCard,
        child: Ink(
          decoration: BoxDecoration(
            color: CH.paper,
            borderRadius: ChRadii.rCard,
            boxShadow: ChShadows.card,
            border: selected ? Border.all(color: CH.hot, width: 1.5) : null,
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Leading 42 square cream tile with emoji
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: CH.cream,
                  borderRadius: ChRadii.rMd,
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: ChText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: ChText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),
              trailing ?? _RadioDot(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? CH.hot : CH.paper,
        border: Border.all(
          color: selected ? CH.hot : CH.radioBorder,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: CH.paper,
                ),
              ),
            )
          : null,
    );
  }
}
