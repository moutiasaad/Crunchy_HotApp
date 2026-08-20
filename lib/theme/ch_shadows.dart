import 'package:flutter/widgets.dart';

/// Shadow presets from the design-system spec §2.
/// Rule: never more than one shadow per surface.
class ChShadows {
  ChShadows._();

  /// Card (regular product/selection row).
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0D2E1D12),          // rgba(46,29,18, .05)
      offset: Offset(0, 6),
      blurRadius: 18,
      spreadRadius: 0,
    ),
  ];

  /// Raised / featured card.
  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x142E1D12),          // rgba(46,29,18, .08)
      offset: Offset(0, 10),
      blurRadius: 26,
      spreadRadius: 0,
    ),
  ];

  /// Primary orange CTA glow.
  static const List<BoxShadow> primaryButton = [
    BoxShadow(
      color: Color(0x66EE4E1B),          // rgba(238,78,27, .40)
      offset: Offset(0, 12),
      blurRadius: 26,
      spreadRadius: 0,
    ),
  ];

  /// Chip when selected (softer glow than the primary CTA).
  static const List<BoxShadow> chipSelected = [
    BoxShadow(
      color: Color(0x47EE4E1B),          // rgba(238,78,27, .28)
      offset: Offset(0, 8),
      blurRadius: 18,
      spreadRadius: 0,
    ),
  ];

  /// Dark header logo dramatic drop shadow.
  static const List<BoxShadow> darkHeaderLogo = [
    BoxShadow(
      color: Color(0x73000000),          // rgba(0,0,0, .45)
      offset: Offset(0, 14),
      blurRadius: 34,
      spreadRadius: 0,
    ),
  ];
}
