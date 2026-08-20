import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Stadium product badge. Cairo 800 11, padding 5×11.
enum ChBadgeKind { spicy, popular, light, isNew, custom }

class ChBadge extends StatelessWidget {
  final String label;
  final ChBadgeKind kind;
  final Color? bg;
  final Color? fg;

  const ChBadge({
    super.key,
    required this.label,
    this.kind = ChBadgeKind.custom,
    this.bg,
    this.fg,
  });

  /// 🔥 حار — red/white.
  const ChBadge.spicy({super.key, this.label = '🔥 حار'})
      : kind = ChBadgeKind.spicy, bg = null, fg = null;

  /// ⭐ الأشهر — yellow/char.
  const ChBadge.popular({super.key, this.label = '⭐ الأشهر'})
      : kind = ChBadgeKind.popular, bg = null, fg = null;

  /// 🥗 خفيف — green/white.
  const ChBadge.light({super.key, this.label = '🥗 خفيف'})
      : kind = ChBadgeKind.light, bg = null, fg = null;

  /// جديد — char/white.
  const ChBadge.isNew({super.key, this.label = 'جديد'})
      : kind = ChBadgeKind.isNew, bg = null, fg = null;

  ({Color bg, Color fg}) _colors() {
    switch (kind) {
      case ChBadgeKind.spicy:   return (bg: CH.red,    fg: CH.paper);
      case ChBadgeKind.popular: return (bg: CH.yellow, fg: CH.char);
      case ChBadgeKind.light:   return (bg: CH.green,  fg: CH.paper);
      case ChBadgeKind.isNew:   return (bg: CH.char,   fg: CH.paper);
      case ChBadgeKind.custom:  return (bg: bg ?? CH.cream2, fg: fg ?? CH.ink);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: ChRadii.rStadium,
      ),
      child: Text(
        label,
        style: ChText.micro.copyWith(color: c.fg),
      ),
    );
  }
}

/// Status badge (delivered / cancelled / open / closed).
/// Uses 12% opacity fill of green/red with the same hue as text.
class ChStatusBadge extends StatelessWidget {
  final String label;
  final Color hue; // e.g. CH.green (open), CH.red (closed/cancelled)

  const ChStatusBadge({super.key, required this.label, required this.hue});

  const ChStatusBadge.open({super.key, this.label = 'مفتوح'})       : hue = CH.green;
  const ChStatusBadge.closed({super.key, this.label = 'مغلق'})      : hue = CH.red;
  const ChStatusBadge.delivered({super.key, this.label = 'تم التوصيل'}) : hue = CH.green;
  const ChStatusBadge.cancelled({super.key, this.label = 'ملغى'})   : hue = CH.red;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: CH.status12(hue),
        borderRadius: ChRadii.rStadium,
      ),
      child: Text(label, style: ChText.micro.copyWith(color: hue)),
    );
  }
}
