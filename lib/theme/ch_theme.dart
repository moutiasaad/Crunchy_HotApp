import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ch_colors.dart';
import 'ch_radii.dart';
import 'ch_typography.dart';

/// Central ThemeData for the whole app.
/// Prefer using the CH tokens (ChText, CH.hot, ChRadii.card…) directly in widgets
/// — this ThemeData exists so that native Material widgets (dialogs, snackbars,
/// text fields, etc.) already look on-brand without extra styling.
class ChTheme {
  ChTheme._();

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      // ---------- Colour scheme ----------
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.light,
        primary:            CH.hot,
        onPrimary:          CH.paper,
        primaryContainer:   CH.cream2,
        onPrimaryContainer: CH.ink,
        secondary:          CH.char,
        onSecondary:        CH.paper,
        surface:            CH.paper,
        onSurface:          CH.ink,
        surfaceContainerHighest: CH.cream,
        error:              CH.red,
        onError:            CH.paper,
        outline:            CH.line,
        outlineVariant:     CH.line,
      ),

      // ---------- Backgrounds ----------
      scaffoldBackgroundColor: CH.cream,
      canvasColor:             CH.cream,
      dividerColor:            CH.line,

      // ---------- Typography ----------
      textTheme: TextTheme(
        displayLarge:   ChText.display,
        displayMedium:  ChText.h1,
        displaySmall:   ChText.h2,
        headlineLarge:  ChText.h1,
        headlineMedium: ChText.h2,
        headlineSmall:  ChText.h3,
        titleLarge:     ChText.h3,
        titleMedium:    ChText.cardTitle,
        titleSmall:     ChText.label,
        bodyLarge:      ChText.body.copyWith(fontSize: 15),
        bodyMedium:     ChText.body,
        bodySmall:      ChText.caption,
        labelLarge:     ChText.label,
        labelMedium:    ChText.micro,
        labelSmall:     ChText.micro,
      ),

      // ---------- AppBar (rarely used — most screens use ChDarkHeader) ----------
      appBarTheme: AppBarTheme(
        backgroundColor: CH.paper,
        foregroundColor: CH.ink,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: ChText.cardTitle,
        iconTheme: const IconThemeData(color: CH.ink, size: 24),
      ),

      // ---------- Icons ----------
      iconTheme: const IconThemeData(color: CH.ink, size: 22),

      // ---------- Buttons (Material defaults; prefer ChButton widgets) ----------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CH.hot,
          foregroundColor: CH.paper,
          disabledBackgroundColor: CH.line,
          disabledForegroundColor: CH.inactive,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: ChRadii.rXl),
          textStyle: ChText.button,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CH.ink,
          side: const BorderSide(color: CH.line, width: 1.5),
          shape: const RoundedRectangleBorder(borderRadius: ChRadii.rMd),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: ChText.label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CH.hot,
          textStyle: ChText.label,
        ),
      ),

      // ---------- Inputs ----------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CH.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: ChText.body.copyWith(color: CH.muted),
        labelStyle: ChText.label.copyWith(color: CH.muted),
        border: const OutlineInputBorder(
          borderRadius: ChRadii.rLg,
          borderSide: BorderSide(color: CH.line, width: 1.5),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: ChRadii.rLg,
          borderSide: BorderSide(color: CH.line, width: 1.5),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: ChRadii.rLg,
          borderSide: BorderSide(color: CH.hot, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: ChRadii.rLg,
          borderSide: BorderSide(color: CH.red, width: 1.5),
        ),
      ),

      // ---------- Chip (fallback; prefer ChChip) ----------
      chipTheme: ChipThemeData(
        backgroundColor: CH.paper,
        selectedColor: CH.hot,
        disabledColor: CH.line,
        labelStyle: ChText.label,
        secondaryLabelStyle: ChText.label.copyWith(color: CH.paper),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: const StadiumBorder(side: BorderSide(color: CH.line, width: 1.5)),
        side: const BorderSide(color: CH.line, width: 1.5),
      ),

      // ---------- Cards ----------
      cardTheme: const CardThemeData(
        color: CH.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: ChRadii.rCard),
      ),

      // ---------- Bottom sheets ----------
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CH.paper,
        surfaceTintColor: CH.paper,
        shape: RoundedRectangleBorder(borderRadius: ChRadii.rBottomSheet),
      ),

      // ---------- Dividers ----------
      dividerTheme: const DividerThemeData(
        color: CH.line,
        thickness: 1,
        space: 1,
      ),

      // ---------- Switches (small tweak — the real UI uses ChSwitch) ----------
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => CH.paper),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? CH.green : const Color(0xFFE2D3C3),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ---------- Splash / ripple ----------
      splashColor: CH.hot.withValues(alpha: 0.10),
      highlightColor: CH.hot.withValues(alpha: 0.06),

      // ---------- Google-Fonts default text theme (fallback if a widget forgets to set one) ----------
      primaryTextTheme: GoogleFonts.cairoTextTheme(base.textTheme).apply(
        bodyColor: CH.ink,
        displayColor: CH.ink,
      ),
    );
  }
}
