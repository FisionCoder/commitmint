import 'package:flutter/material.dart';

/// Central palette + theme for the app. Modeled on a dark Git client look.
class AppColors {
  AppColors._();

  // Surfaces — neutral blue-grey dark (no colour cast), modern and clean.
  static const Color background = Color(0xFF14181E); // window background
  static const Color surface = Color(0xFF181D24); // panels
  static const Color surfaceAlt = Color(0xFF1C222A); // sidebars
  static const Color surfaceRaised = Color(0xFF232A33); // cards / inputs
  static const Color titleBar = Color(0xFF0D1116);

  // Lines & dividers
  static const Color border = Color(0xFF2A323D);
  static const Color borderSubtle = Color(0xFF1E252D);

  // Text
  static const Color textPrimary = Color(0xFFE6EAF0);
  static const Color textSecondary = Color(0xFF9AA4B2);
  static const Color textMuted = Color(0xFF687180);

  // Accent — mint. [accent] is deep enough to keep white text readable;
  // [accentTeal] is the brighter mint used for highlights/gradients.
  static const Color accent = Color(0xFF14B8A6); // mint / teal
  static const Color accentTeal = Color(0xFF2DD4BF); // bright mint
  static const Color selection = Color(0xFF123F37); // mint-tinted selection
  static const Color selectionRow = Color(0xFF0F3A32); // mint-tinted row

  // Status
  static const Color green = Color(0xFF4ADE80);
  static const Color red = Color(0xFFF87171);
  static const Color amber = Color(0xFFFBBF24);
  static const Color purple = Color(0xFFA78BFA);

  // Graph lane colors (cycled per lane) — lead with mint, keep variety.
  static const List<Color> lanes = [
    Color(0xFF2DD4BF), // mint
    Color(0xFF34D399), // emerald
    Color(0xFF60A5FA), // blue
    Color(0xFFA78BFA), // purple
    Color(0xFFFBBF24), // amber
    Color(0xFFF472B6), // pink
    Color(0xFF22D3EE), // cyan
    Color(0xFF4ADE80), // green
  ];
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.surface,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.surface,
        primary: AppColors.accent,
        secondary: AppColors.accentTeal,
        error: AppColors.red,
        onSurface: AppColors.textPrimary,
      ),
      dividerColor: AppColors.border,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 18),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: Color(0xFF2A323D),
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        textStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
        waitDuration: Duration(milliseconds: 500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(const Color(0xFF3A434F)),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
      // Readable snackbars by default: light text on the raised surface (the
      // M3 default uses an inverse light background that washed out our text).
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle:
            const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
