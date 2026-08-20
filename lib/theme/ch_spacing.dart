/// Spacing tokens from the design-system spec §4.
/// Vertical rhythm: 4 / 6 / 8 / 10 / 12 / 14 / 18 / 22 / 26.
class ChSpacing {
  ChSpacing._();

  static const double x4  = 4;
  static const double x6  = 6;
  static const double x8  = 8;
  static const double x10 = 10;
  static const double x12 = 12;
  static const double x14 = 14;
  static const double x18 = 18;
  static const double x22 = 22;
  static const double x26 = 26;
  static const double x30 = 30;

  // Horizontal padding presets
  static const double gutterContent = 16;  // content cards
  static const double gutterText    = 20;  // titles, text-only blocks, bars

  // Vertical presets
  static const double statusBarTop  = 54;  // when no app bar
  static const double barSafeBottom = 26;

  // Gaps
  static const double cardGap    = 12;
  static const double sectionGap = 22;
}
