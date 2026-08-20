import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Segmented toggle: two equal buttons (delivery / pickup, or delivery/pickup on cart).
/// Selected: char fill + white. Unselected: white + inset 1.5 line.
class ChSegmented<T> extends StatelessWidget {
  final List<ChSegmentedItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  const ChSegmented({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(items.length, (i) {
        final it = items[i];
        final active = it.value == selected;
        return Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              end: i == items.length - 1 ? 0 : 8,
            ),
            child: Material(
              color: active ? CH.char : CH.paper,
              borderRadius: ChRadii.rLg,
              child: InkWell(
                borderRadius: ChRadii.rLg,
                onTap: () => onChanged(it.value),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: ChRadii.rLg,
                    border: active ? null : Border.all(color: CH.line, width: 1.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (it.emoji != null) ...[
                        Text(it.emoji!, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        it.label,
                        style: ChText.label.copyWith(
                          color: active ? CH.paper : CH.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class ChSegmentedItem<T> {
  final T value;
  final String label;
  final String? emoji;
  const ChSegmentedItem({required this.value, required this.label, this.emoji});
}
