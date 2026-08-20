import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Order-tracking timeline. Per step: 28 circle + 2px connector.
/// Done → green + ✓ · current → hot + emoji, label in hot · upcoming → idle fill, label inactive.
class ChTimeline extends StatelessWidget {
  final List<ChTimelineStep> steps;
  final int currentIndex;

  const ChTimeline({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final isDone   = i < currentIndex;
        final isActive = i == currentIndex;
        final isLast   = i == steps.length - 1;

        final circleColor = isDone
            ? CH.green
            : isActive ? CH.hot : CH.timelineIdle;
        final circleChild = isDone
            ? const Icon(Icons.check, color: CH.paper, size: 16)
            : Text(step.emoji, style: const TextStyle(fontSize: 14));
        final labelColor = isDone
            ? CH.ink
            : isActive ? CH.hot : CH.inactive;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: circleChild,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: isDone ? CH.green : CH.timelineIdle,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: ChText.bodyStrong.copyWith(color: labelColor),
                      ),
                      if (step.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(step.subtitle!, style: ChText.caption),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class ChTimelineStep {
  final String title;
  final String? subtitle;
  final String emoji;
  const ChTimelineStep({required this.title, required this.emoji, this.subtitle});
}
