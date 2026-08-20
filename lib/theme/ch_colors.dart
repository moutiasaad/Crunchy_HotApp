import 'package:flutter/material.dart';

/// Crunchy Hot brand colours — locked from the design-system spec §2.
/// Every screen must pull from here; never hard-code hex.
class CH {
  CH._();

  // Primary brand
  static const Color hot      = Color(0xFFEE4E1B); // CTAs, prices, active tab
  static const Color hotDeep  = Color(0xFFC63A0F); // Pressed state
  static const Color hotSoft  = Color(0xFFFF7A45); // Accents on dark

  // Dark chrome
  static const Color char     = Color(0xFF1A1210); // Headers, splash, secondary buttons
  static const Color brown    = Color(0xFF2E1D12); // Deep alt

  // Cream backgrounds
  static const Color cream    = Color(0xFFFFF3E6); // Screen background
  static const Color cream2   = Color(0xFFFBE7D2); // Image placeholders, subtle tiles
  static const Color paper    = Color(0xFFFFFFFF); // Cards, sheets, bars

  // Text
  static const Color ink      = Color(0xFF241611); // Primary text
  static const Color muted    = Color(0xFF8A7A6E); // Secondary text
  static const Color line     = Color(0xFFEEDDCA); // Borders, dividers
  static const Color inactive = Color(0xFFB3A396); // Inactive icons

  // Semantic
  static const Color yellow   = Color(0xFFFFC02E); // Points, "popular"
  static const Color red      = Color(0xFFE11D2A); // Spicy, destructive
  static const Color green    = Color(0xFF2FA84F); // Success, open, delivered

  // Dark-header text ramps
  static const Color darkHeaderMuted     = Color(0xFFA89684); // secondary label
  static const Color darkHeaderBody      = Color(0xFFC9B6A6); // body copy
  static const Color darkHeaderBodyBold  = Color(0xFFD9C7B8); // stronger

  // Radio unselected border in selection rows
  static const Color radioBorder = Color(0xFFDCCBBA);
  // Bottom-nav top border
  static const Color navTopBorder = Color(0xFFF0E4D6);
  // Timeline upcoming step fill
  static const Color timelineIdle = Color(0xFFE6D6C6);
  // Discount pill background on hero
  static const Color discountOnHot = Color(0xFFFFD0BB);

  /// 12% opacity variant of any status colour (for status-badge fills).
  static Color status12(Color c) => c.withAlpha(0x1F);
}
