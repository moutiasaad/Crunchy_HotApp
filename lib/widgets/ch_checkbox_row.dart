import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/ch_formatters.dart';

/// Add-on checkbox row: white, radius 14, 1.5 line border (→ hot when checked).
/// 22 square checkbox radius 7. Trailing `+ price` in hot.
class ChCheckboxRow extends StatelessWidget {
  final String label;
  final int priceDelta; // in SYP; 0 = no trailing price
  final bool checked;
  final ValueChanged<bool> onChanged;

  const ChCheckboxRow({
    super.key,
    required this.label,
    required this.checked,
    required this.onChanged,
    this.priceDelta = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CH.paper,
      borderRadius: ChRadii.rXl,
      child: InkWell(
        onTap: () => onChanged(!checked),
        borderRadius: ChRadii.rXl,
        child: Ink(
          decoration: BoxDecoration(
            color: CH.paper,
            borderRadius: ChRadii.rXl,
            border: Border.all(
              color: checked ? CH.hot : CH.line,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // 22 square checkbox
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: checked ? CH.hot : CH.paper,
                  borderRadius: const BorderRadius.all(Radius.circular(ChRadii.xxs)),
                  border: Border.all(color: checked ? CH.hot : CH.line, width: 1.5),
                ),
                child: checked ? const Icon(Icons.check, size: 16, color: CH.paper) : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: ChText.bodyStrong)),
              if (priceDelta != 0)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '+ ${ChMoney.format(priceDelta)}',
                    style: ChText.label.copyWith(color: CH.hot, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
