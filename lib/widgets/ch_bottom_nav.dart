import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Bottom tab bar — white, top border navTopBorder, 5 items, pinned.
/// Item: 20px emoji + Cairo 800 11 label; active `hot`, inactive `inactive`.
/// Cart badge: stadium min 18×18, hot fill, white 11.
class ChBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int cartCount;

  const ChBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.cartCount = 0,
  });

  static const _items = <_TabItem>[
    _TabItem(emoji: '🏠', label: 'الرئيسية'),
    _TabItem(emoji: '📋', label: 'المنيو'),
    _TabItem(emoji: '🛒', label: 'السلة'),
    _TabItem(emoji: '📦', label: 'طلباتي'),
    _TabItem(emoji: '👤', label: 'حسابي'),
  ];

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
          padding: const EdgeInsets.only(top: 12, bottom: 26),
          child: Row(
            children: List.generate(_items.length, (i) {
              final it = _items[i];
              final active = i == currentIndex;
              final showBadge = i == 2 && cartCount > 0;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 24,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: Center(
                                child: Text(
                                  it.emoji,
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: active ? CH.hot : CH.inactive,
                                  ),
                                ),
                              ),
                            ),
                            if (showBadge)
                              PositionedDirectional(
                                top: -4, start: 26,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: CH.hot,
                                    borderRadius: ChRadii.rStadium,
                                  ),
                                  child: Text(
                                    '$cartCount',
                                    textAlign: TextAlign.center,
                                    style: ChText.micro.copyWith(color: CH.paper),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        it.label,
                        style: ChText.micro.copyWith(
                          color: active ? CH.hot : CH.inactive,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String emoji;
  final String label;
  const _TabItem({required this.emoji, required this.label});
}
