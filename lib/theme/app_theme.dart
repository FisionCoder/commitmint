import 'package:flutter/material.dart';

/// A complete colour palette for one theme (dark or light).
class Palette {
  final Brightness brightness;
  final Color background, surface, surfaceAlt, surfaceRaised, titleBar;
  final Color border, borderSubtle;
  final Color textPrimary, textSecondary, textMuted;
  final Color accent, accentTeal, selection, selectionRow;
  final Color green, red, amber, purple;
  final Color tooltip, tooltipText, scrollbarThumb;
  final Color terminalBackground, terminalForeground;
  final List<Color> lanes;

  const Palette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceRaised,
    required this.titleBar,
    required this.border,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentTeal,
    required this.selection,
    required this.selectionRow,
    required this.green,
    required this.red,
    required this.amber,
    required this.purple,
    required this.tooltip,
    required this.tooltipText,
    required this.scrollbarThumb,
    required this.terminalBackground,
    required this.terminalForeground,
    required this.lanes,
  });
}

/// Dark theme — neutral blue-grey with a mint accent.
const Palette darkPalette = Palette(
  brightness: Brightness.dark,
  background: Color(0xFF14181E),
  surface: Color(0xFF181D24),
  surfaceAlt: Color(0xFF1C222A),
  surfaceRaised: Color(0xFF232A33),
  titleBar: Color(0xFF0D1116),
  border: Color(0xFF2A323D),
  borderSubtle: Color(0xFF1E252D),
  textPrimary: Color(0xFFE6EAF0),
  textSecondary: Color(0xFF9AA4B2),
  textMuted: Color(0xFF687180),
  accent: Color(0xFF14B8A6),
  accentTeal: Color(0xFF2DD4BF),
  selection: Color(0xFF123F37),
  selectionRow: Color(0xFF0F3A32),
  green: Color(0xFF4ADE80),
  red: Color(0xFFF87171),
  amber: Color(0xFFFBBF24),
  purple: Color(0xFFA78BFA),
  tooltip: Color(0xFF2A323D),
  tooltipText: Color(0xFFE6EAF0),
  scrollbarThumb: Color(0xFF3A434F),
  terminalBackground: Color(0xFF11151B),
  terminalForeground: Color(0xFFE8EDEA),
  lanes: [
    Color(0xFF2DD4BF), // mint
    Color(0xFF34D399), // emerald
    Color(0xFF60A5FA), // blue
    Color(0xFFA78BFA), // purple
    Color(0xFFFBBF24), // amber
    Color(0xFFF472B6), // pink
    Color(0xFF22D3EE), // cyan
    Color(0xFF4ADE80), // green
  ],
);

/// Light theme — soft off-white with the same mint accent (deepened so white
/// text on accent stays readable).
const Palette lightPalette = Palette(
  brightness: Brightness.light,
  background: Color(0xFFE8ECEA),
  surface: Color(0xFFF4F6F5),
  surfaceAlt: Color(0xFFEAEEEC),
  surfaceRaised: Color(0xFFFFFFFF),
  titleBar: Color(0xFFDCE2DF),
  border: Color(0xFFCDD5D1),
  borderSubtle: Color(0xFFDCE2DF),
  textPrimary: Color(0xFF1A211E),
  textSecondary: Color(0xFF4C5852),
  textMuted: Color(0xFF808C85),
  accent: Color(0xFF0D9488),
  accentTeal: Color(0xFF14B8A6),
  selection: Color(0xFFC6E9E2),
  selectionRow: Color(0xFFDCF1ED),
  green: Color(0xFF16A34A),
  red: Color(0xFFDC2626),
  amber: Color(0xFFB45309),
  purple: Color(0xFF7C3AED),
  tooltip: Color(0xFF2D3A34),
  tooltipText: Color(0xFFF4F6F5),
  scrollbarThumb: Color(0xFFB3BDB8),
  terminalBackground: Color(0xFFF7F9F8),
  terminalForeground: Color(0xFF1A211E),
  lanes: [
    Color(0xFF0D9488), // mint
    Color(0xFF059669), // emerald
    Color(0xFF2563EB), // blue
    Color(0xFF7C3AED), // purple
    Color(0xFFB45309), // amber
    Color(0xFFDB2777), // pink
    Color(0xFF0891B2), // cyan
    Color(0xFF16A34A), // green
  ],
);

/// The active palette's colours, exposed as plain statics so the whole app can
/// reference `AppColors.x` without a BuildContext. Call [apply] to switch
/// themes, then trigger a full rebuild so widgets re-read these values.
class AppColors {
  AppColors._();

  static Brightness brightness = darkPalette.brightness;
  static Color background = darkPalette.background;
  static Color surface = darkPalette.surface;
  static Color surfaceAlt = darkPalette.surfaceAlt;
  static Color surfaceRaised = darkPalette.surfaceRaised;
  static Color titleBar = darkPalette.titleBar;
  static Color border = darkPalette.border;
  static Color borderSubtle = darkPalette.borderSubtle;
  static Color textPrimary = darkPalette.textPrimary;
  static Color textSecondary = darkPalette.textSecondary;
  static Color textMuted = darkPalette.textMuted;
  static Color accent = darkPalette.accent;
  static Color accentTeal = darkPalette.accentTeal;
  static Color selection = darkPalette.selection;
  static Color selectionRow = darkPalette.selectionRow;
  static Color green = darkPalette.green;
  static Color red = darkPalette.red;
  static Color amber = darkPalette.amber;
  static Color purple = darkPalette.purple;
  static Color tooltip = darkPalette.tooltip;
  static Color tooltipText = darkPalette.tooltipText;
  static Color scrollbarThumb = darkPalette.scrollbarThumb;
  static Color terminalBackground = darkPalette.terminalBackground;
  static Color terminalForeground = darkPalette.terminalForeground;
  static List<Color> lanes = darkPalette.lanes;

  static void apply(Palette p) {
    brightness = p.brightness;
    background = p.background;
    surface = p.surface;
    surfaceAlt = p.surfaceAlt;
    surfaceRaised = p.surfaceRaised;
    titleBar = p.titleBar;
    border = p.border;
    borderSubtle = p.borderSubtle;
    textPrimary = p.textPrimary;
    textSecondary = p.textSecondary;
    textMuted = p.textMuted;
    accent = p.accent;
    accentTeal = p.accentTeal;
    selection = p.selection;
    selectionRow = p.selectionRow;
    green = p.green;
    red = p.red;
    amber = p.amber;
    purple = p.purple;
    tooltip = p.tooltip;
    tooltipText = p.tooltipText;
    scrollbarThumb = p.scrollbarThumb;
    terminalBackground = p.terminalBackground;
    terminalForeground = p.terminalForeground;
    lanes = p.lanes;
  }
}

class AppTheme {
  /// Builds the Material [ThemeData] for the given palette.
  static ThemeData from(Palette p) {
    final base = p.brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      canvasColor: p.surface,
      colorScheme: base.colorScheme.copyWith(
        brightness: p.brightness,
        surface: p.surface,
        primary: p.accent,
        secondary: p.accentTeal,
        error: p.red,
        onSurface: p.textPrimary,
      ),
      dividerColor: p.border,
      textTheme: base.textTheme.apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      iconTheme: IconThemeData(color: p.textSecondary, size: 18),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.tooltip,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
        ),
        textStyle: TextStyle(color: p.tooltipText, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.background,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        hintStyle: TextStyle(color: p.textMuted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: p.accent),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(p.scrollbarThumb),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceRaised,
        contentTextStyle: TextStyle(color: p.textPrimary, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: p.border),
        ),
      ),
    );
  }
}
