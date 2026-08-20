import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'ch_button.dart';

/// Centered empty state: 56px emoji, Changa 800 18 title, caption body, dark pill CTA.
class ChEmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const ChEmptyState({
    super.key,
    required this.emoji,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: ChText.cardTitle.copyWith(fontSize: 18),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center, style: ChText.caption),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 20),
              ChDarkButton(
                label: ctaLabel!,
                onPressed: onCta,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
