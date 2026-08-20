import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/ch_formatters.dart';
import 'ch_image_placeholder.dart';

/// Featured card: white, radius 20, 16:9 image on top with badge pinned 10 from top/trailing,
/// info row below with `+` button. Raised shadow.
class ChFeaturedCard extends StatelessWidget {
  final String name;
  final int price;
  final String? imageUrl;
  final Widget? badge;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;

  const ChFeaturedCard({
    super.key,
    required this.name,
    required this.price,
    this.imageUrl,
    this.badge,
    this.onTap,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CH.paper,
      borderRadius: ChRadii.rFeatured,
      child: InkWell(
        onTap: onTap,
        borderRadius: ChRadii.rFeatured,
        child: Ink(
          decoration: BoxDecoration(
            color: CH.paper,
            borderRadius: ChRadii.rFeatured,
            boxShadow: ChShadows.raised,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 16:9 image with badge
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft:  Radius.circular(ChRadii.featured),
                  topRight: Radius.circular(ChRadii.featured),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    children: [
                      const Positioned.fill(child: ChImagePlaceholder(borderRadius: BorderRadius.zero)),
                      if (badge != null)
                        PositionedDirectional(top: 10, end: 10, child: badge!),
                    ],
                  ),
                ),
              ),
              // Info row
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: ChText.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(ChMoney.format(price), style: ChText.price),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 40, height: 40,
                      child: Material(
                        color: CH.char,
                        borderRadius: ChRadii.rSm,
                        child: InkWell(
                          onTap: onAdd,
                          borderRadius: ChRadii.rSm,
                          child: const Icon(Icons.add, color: CH.paper, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
