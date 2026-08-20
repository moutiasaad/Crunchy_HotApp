import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Custom switch (46×26 track radius 999, #E2D3C3 → green when on, 20 white knob, padding 3).
class ChSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const ChSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 46, height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? CH.green : const Color(0xFFE2D3C3),
          borderRadius: ChRadii.rStadium,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
          child: Container(
            width: 20, height: 20,
            decoration: const BoxDecoration(
              color: CH.paper,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
