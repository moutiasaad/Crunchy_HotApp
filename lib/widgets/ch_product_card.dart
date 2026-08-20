import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'ch_image_placeholder.dart';

/// Product row card (used in menu, search, favourites list).
/// White, radius 18, padding 12, card shadow.
/// Leading 78–80 square image radius 13, body (name / desc / price + optional kcal),
/// trailing 36 dark `+` button. Optional heart top-trailing (14px).
class ChProductCard extends StatelessWidget {
  final String name;
  final String description;
  final int price;
  final String? kcal;
  final String? imageUrl;
  final Widget? badge;
  final bool favourite;
  final ValueChanged<bool>? onFavouriteChanged;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;
  final bool disabled;

  const ChProductCard({
    super.key,
    required this.name,
    required this.description,
    required this.price,
    this.kcal,
    this.imageUrl,
    this.badge,
    this.favourite = false,
    this.onFavouriteChanged,
    this.onTap,
    this.onAdd,
    this.disabled = false,
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
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading image (with badge + favourite overlay)
              SizedBox(
                width: 78, height: 78,
                child: Stack(
                  children: [
                    const Positioned.fill(child: ChImagePlaceholder(borderRadius: ChRadii.rLg)),
                    if (badge != null)
                      PositionedDirectional(top: 4, start: 4, child: badge!),
                    if (onFavouriteChanged != null)
                      PositionedDirectional(
                        top: 2, end: 2,
                        child: GestureDetector(
                          onTap: () => onFavouriteChanged!(!favourite),
                          child: Text(
                            favourite ? '❤️' : '🤍',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Body
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(name,
                        style: ChText.cardTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(description,
                        style: ChText.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            _fmtPrice(price),
                            style: ChText.price,
                          ),
                        ),
                        if (kcal != null) ...[
                          const SizedBox(width: 8),
                          Text('·', style: ChText.caption),
                          const SizedBox(width: 8),
                          Text(kcal!,
                              style: ChText.caption.copyWith(color: CH.darkHeaderBody, fontSize: 12)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Trailing `+` button (dark 36×36)
              SizedBox(
                width: 36, height: 36,
                child: Material(
                  color: disabled ? CH.line : CH.char,
                  borderRadius: ChRadii.rSm,
                  child: InkWell(
                    onTap: disabled ? null : onAdd,
                    borderRadius: ChRadii.rSm,
                    child: Icon(
                      Icons.add,
                      color: disabled ? CH.inactive : CH.paper,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtPrice(int p) {
    // Simple thousands separator; a full formatter lives in ChMoney
    final s = p.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${buf.toString()} ل.س';
  }
}
