import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Sticky primary CTA bar at the bottom of a screen (used on cart/checkout/detail).
/// White fill, top border, padding 14/20/30, single primary button provided as child.
class ChBottomActionBar extends StatelessWidget {
  final Widget child;

  const ChBottomActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: CH.paper,
        border: Border(top: BorderSide(color: CH.navTopBorder, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          child: child,
        ),
      ),
    );
  }
}
