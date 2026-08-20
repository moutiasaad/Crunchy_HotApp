import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import 'ch_button.dart';

/// Weekly offer banner. Hot fill, radius 20–22, radial darkening at one corner,
/// yellow kicker pill, white Changa 800 22, old price struck through in #FFD0BB,
/// new price white, dark CTA inside.
class ChOfferBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final int newPrice;
  final int? oldPrice;
  final String kicker;
  final String ctaLabel;
  final VoidCallback? onCta;

  const ChOfferBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.newPrice,
    this.oldPrice,
    this.kicker = 'عرض هذا الأسبوع',
    this.ctaLabel = 'أضف العرض للسلة',
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CH.hot,
        borderRadius: ChRadii.rFeatured,
      ),
      child: Stack(
        children: [
          // Radial darkening at one corner
          PositionedDirectional(
            top: -50, end: -50, width: 200, height: 200,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x40000000), Colors.transparent],
                  stops: [0.0, 0.9],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Yellow kicker pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: CH.yellow,
                    borderRadius: ChRadii.rStadium,
                  ),
                  child: Text(kicker, style: ChText.micro.copyWith(color: CH.char)),
                ),
                const SizedBox(height: 10),

                Text(title,
                    style: ChText.h2.copyWith(color: CH.paper, fontSize: 22)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: ChText.body.copyWith(color: CH.discountOnHot)),
                const SizedBox(height: 14),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (oldPrice != null) ...[
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          ChMoney.format(oldPrice!),
                          style: ChText.label.copyWith(
                            color: CH.discountOnHot,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: CH.discountOnHot,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        ChMoney.format(newPrice),
                        style: ChText.h2.copyWith(color: CH.paper, fontSize: 22),
                      ),
                    ),
                    const Spacer(),
                    ChDarkButton(label: ctaLabel, onPressed: onCta),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
