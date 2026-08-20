import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ch_colors.dart';

/// Type scale from the design-system spec §3.
///
/// Rule of thumb:
///  - Anything "shouted" (titles, prices, big numbers)  → Changa 800.
///  - Everything else → Cairo. UI labels are Cairo 700/800 (Arabic reads weak below 600).
///  - Never let Arabic line-height drop below 1.3.
class ChText {
  ChText._();

  // --- Display / headings (Changa 800) ---
  static TextStyle display   = GoogleFonts.changa(fontSize: 34, fontWeight: FontWeight.w800, height: 1.35, color: CH.ink);
  static TextStyle h1        = GoogleFonts.changa(fontSize: 27, fontWeight: FontWeight.w800, height: 1.3,  color: CH.ink);
  static TextStyle h2        = GoogleFonts.changa(fontSize: 23, fontWeight: FontWeight.w800, height: 1.3,  color: CH.ink);
  static TextStyle h3        = GoogleFonts.changa(fontSize: 20, fontWeight: FontWeight.w800, height: 1.3,  color: CH.ink);
  static TextStyle cardTitle = GoogleFonts.changa(fontSize: 17, fontWeight: FontWeight.w800, height: 1.35, color: CH.ink);

  // --- Prices & totals (Changa 800, color varies) ---
  static TextStyle price     = GoogleFonts.changa(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2, color: CH.hot);
  static TextStyle priceLg   = GoogleFonts.changa(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2, color: CH.hot);
  static TextStyle total     = GoogleFonts.changa(fontSize: 19, fontWeight: FontWeight.w800, height: 1.3, color: CH.ink);
  static TextStyle metric    = GoogleFonts.changa(fontSize: 52, fontWeight: FontWeight.w800, height: 1.0, color: CH.ink);

  // --- Body & UI labels (Cairo) ---
  static TextStyle body        = GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w400, height: 1.75, color: CH.ink);
  static TextStyle bodyStrong  = GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w800, height: 1.4,  color: CH.ink);
  static TextStyle label       = GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, height: 1.4,  color: CH.ink);
  static TextStyle caption     = GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, height: 1.6,  color: CH.muted);
  static TextStyle micro       = GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w800, height: 1.3,  color: CH.ink);

  // --- Buttons (Changa 800) ---
  static TextStyle button      = GoogleFonts.changa(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2, color: CH.paper);

  // --- Kickers / latin sub-wordmarks (letter-spacing 2–3) ---
  static TextStyle kicker      = GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w800, height: 1.3, letterSpacing: 2.5, color: CH.hotSoft);

  /// Convenience: apply a colour to any existing style without losing its metrics.
  static TextStyle withColor(TextStyle base, Color color) => base.copyWith(color: color);
}
