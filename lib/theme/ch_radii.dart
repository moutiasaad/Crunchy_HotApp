import 'package:flutter/widgets.dart';

/// Corner-radius tokens from the design-system spec §4.
/// Rule: never one-off values; pick the closest token.
class ChRadii {
  ChRadii._();

  // Small elements
  static const double xxs = 7;   // checkbox
  static const double xs  = 10;  // dashed code box
  static const double sm  = 11;  // quantity stepper, "+ button" in cards
  static const double md  = 12;  // small tiles, icon buttons
  static const double lg  = 13;  // buttons, inputs, dark search field
  static const double xl  = 14;  // add-on checkbox row

  // Cards & sheets
  static const double card    = 18; // product row, selection row
  static const double featured= 20; // featured card, offer banner
  static const double sheet   = 26; // detail sheet, dark header bottom

  static const Radius pill = Radius.circular(999);

  // Prebuilt BorderRadius shortcuts
  static const BorderRadius rXs       = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm       = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd       = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg       = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl       = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rCard     = BorderRadius.all(Radius.circular(card));
  static const BorderRadius rFeatured = BorderRadius.all(Radius.circular(featured));

  // Dark header rounds only the bottom corners
  static const BorderRadius rDarkHeader = BorderRadius.only(
    bottomLeft:  Radius.circular(sheet),
    bottomRight: Radius.circular(sheet),
  );

  // Bottom sheet / detail sheet — rounds only the top corners
  static const BorderRadius rBottomSheet = BorderRadius.only(
    topLeft:  Radius.circular(sheet),
    topRight: Radius.circular(sheet),
  );

  static const BorderRadius rStadium = BorderRadius.all(pill);
}
