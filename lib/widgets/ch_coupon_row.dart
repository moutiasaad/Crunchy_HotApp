import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Coupon row: white radius 18 padding 14.
/// Leading 56 cream tile radius 16 with percent in Changa 800 18 + "خصم" 9px.
/// Trailing dashed 1.5 hot code box radius 10.
class ChCouponRow extends StatelessWidget {
  final int percent;
  final String code;
  final String title;
  final String subtitle;
  final VoidCallback? onCopy;

  const ChCouponRow({
    super.key,
    required this.percent,
    required this.code,
    required this.title,
    required this.subtitle,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CH.paper,
        borderRadius: ChRadii.rCard,
        boxShadow: ChShadows.card,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Leading percent tile
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: CH.cream,
              borderRadius: const BorderRadius.all(Radius.circular(16)),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$percent%', style: ChText.h3.copyWith(color: CH.hot, fontSize: 18)),
                Text('خصم', style: ChText.micro.copyWith(color: CH.muted, fontSize: 9)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ChText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle, style: ChText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onCopy,
            child: CustomPaint(
              painter: _DashedBorderPainter(color: CH.hot, radius: 10, dashWidth: 4, dashSpace: 3),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(code, style: ChText.label.copyWith(color: CH.hot, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashSpace;
  _DashedBorderPainter({required this.color, required this.radius, required this.dashWidth, required this.dashSpace});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rect);
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      double dist = 0;
      while (dist < m.length) {
        final next = dist + dashWidth;
        canvas.drawPath(m.extractPath(dist, next.clamp(0, m.length)), paint);
        dist = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.dashWidth != dashWidth || old.dashSpace != dashSpace;
}
