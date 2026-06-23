import 'package:flutter/material.dart';

/// Central palette + theme for the app. Modeled on a dark Git client look.
class AppColors {
  AppColors._();

  // Surfaces
  static const Color background = Color(0xFF12161C); // window background
  static const Color surface = Color(0xFF181D25); // panels
  static const Color surfaceAlt = Color(0xFF1E242E); // sidebars
  static const Color surfaceRaised = Color(0xFF232A35); // cards / inputs
  static const Color titleBar = Color(0xFF0E1218);

  // Lines & dividers
  static const Color border = Color(0xFF2A323D);
  static const Color borderSubtle = Color(0xFF21272F);

  // Text
  static const Color textPrimary = Color(0xFFE6EAF0);
  static const Color textSecondary = Color(0xFF9AA6B5);
  static const Color textMuted = Color(0xFF697483);

  // Accent
  static const Color accent = Color(0xFF3B82F6); // blue
  static const Color accentTeal = Color(0xFF14B8A6);
  static const Color selection = Color(0xFF1D3A57);
  static const Color selectionRow = Color(0xFF15324C);

  // Status
  static const Color green = Color(0xFF4ADE80);
  static const Color red = Color(0xFFF87171);
  static const Color amber = Color(0xFFFBBF24);
  static const Color purple = Color(0xFFA78BFA);

  // Graph lane colors (cycled per lane)
  static const List<Color> lanes = [
    Color(0xFF4ADE80), // green
    Color(0xFF60A5FA), // blue
    Color(0xFFA78BFA), // purple
    Color(0xFFF472B6), // pink
    Color(0xFFFBBF24), // amber
    Color(0xFF22D3EE), // cyan
    Color(0xFFFB7185), // rose
    Color(0xFF34D399), // emerald
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
