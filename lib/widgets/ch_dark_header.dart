import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Dark header used on Home / Profile / Rewards.
/// `char` background, bottom radius 26, padding 14–20 / 20 / 22–26.
/// Contains: leading location selector, right-side actions, trailing logo.
class ChDarkHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool addRewardsGlow;

  const ChDarkHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 22),
    this.addRewardsGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CH.char,
        borderRadius: ChRadii.rDarkHeader,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (addRewardsGlow)
            const PositionedDirectional(
              top: -30, start: -30, width: 200, height: 200,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x38FFC02E), Colors.transparent],
                    stops: [0.0, 0.85],
                  ),
                ),
              ),
            ),
          SafeArea(
            bottom: false,
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

/// Location selector shown in the dark header on Home.
class ChLocationSelector extends StatelessWidget {
  final String label;   // e.g. "التوصيل إلى"
  final String value;   // e.g. "حلب — الفرقان"
  final VoidCallback? onTap;

  const ChLocationSelector({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: ChRadii.rMd,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place, color: CH.hotSoft, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: ChText.micro.copyWith(color: CH.darkHeaderMuted, fontSize: 11)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(value,
                      style: ChText.bodyStrong.copyWith(color: CH.paper, fontSize: 14)),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: CH.paper),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Yellow points pill shown in the dark header. Tap → RewardsScreen.
///
/// Visual affordance: subtle drop shadow + a trailing "استبدل" label and
/// directional chevron so it reads as a button, not a static badge. The
/// chevron is [Icons.chevron_left] because the pill lives in an RTL screen
/// (Arabic Home header) and "forward/enter" naturally points to the left
/// edge in that reading direction.
class ChPointsPill extends StatelessWidget {
  final int points;
  final VoidCallback? onTap;
  const ChPointsPill({super.key, required this.points, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CH.yellow,
      borderRadius: ChRadii.rStadium,
      elevation: 1.5,
      shadowColor: Colors.black45,
      child: InkWell(
        onTap: onTap,
        borderRadius: ChRadii.rStadium,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⭐', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('$points',
                    style: ChText.micro.copyWith(color: CH.char, fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Container(width: 1, height: 12, color: CH.char.withValues(alpha: 0.18)),
              const SizedBox(width: 6),
              Text('استبدل',
                  style: ChText.micro.copyWith(
                    color: CH.char,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  )),
              const Icon(Icons.chevron_left, size: 16, color: CH.char),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search field styled for the dark header.
class ChDarkSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String>? onChanged;
  const ChDarkSearchField({super.key, this.hint = 'ابحث عن صنف…', this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),  // rgba(255,255,255,.12)
        borderRadius: ChRadii.rLg,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.search, color: CH.darkHeaderBody, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: ChText.body.copyWith(color: CH.paper, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: ChText.body.copyWith(color: CH.darkHeaderBody, fontSize: 14),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
