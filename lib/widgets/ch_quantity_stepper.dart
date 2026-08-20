import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Row inside 1.5 line border radius 11–12, padding 6×10, gap 12–16.
/// `−` / `+` in hot Cairo 800, value Changa 800 centered.
class ChQuantityStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const ChQuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 50,
  });

  @override
  Widget build(BuildContext context) {
    final canMinus = value > min;
    final canPlus  = value < max;

    return Container(
      decoration: BoxDecoration(
        color: CH.paper,
        borderRadius: ChRadii.rSm,
        border: Border.all(color: CH.line, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepBtn(icon: '−', enabled: canMinus, onTap: () => onChanged(value - 1)),
          const SizedBox(width: 14),
          SizedBox(
            width: 20,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: ChText.cardTitle.copyWith(color: CH.ink),
            ),
          ),
          const SizedBox(width: 14),
          _StepBtn(icon: '+', enabled: canPlus, onTap: () => onChanged(value + 1)),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final String icon;
  final bool enabled;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22, height: 22,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: ChRadii.rXs,
        child: Center(
          child: Text(
            icon,
            style: ChText.cardTitle.copyWith(
              color: enabled ? CH.hot : CH.inactive,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }
}
