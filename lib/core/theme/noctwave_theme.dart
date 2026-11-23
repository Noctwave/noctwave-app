import 'package:material_ui/material_ui.dart';

/// Палитры Noctwave: OLED Dark (ТЗ 3.1) и Light — под тему системы.
///
/// Цвета поверхностей/текста переключаются темой; акцент и сигнальные
/// цвета (СТОП, индиго→коралл) общие для обеих вариаций.
abstract final class NoctwavePalette {
  // ── OLED Dark (по умолчанию, ТЗ 3.1) ────────────────────────────────
  static const Color background = Color(0xFF09090B);
  static const Color surface = Color(0xFF141418);
  static const Color outline = Color(0xFF222228);
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFA1A1AA);

  // ── Light (под светлую тему системы) ────────────────────────────────
  static const Color lightBackground = Color(0xFFF7F7F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOutline = Color(0xFFE4E4E9);
  static const Color lightTextPrimary = Color(0xFF131316);
  static const Color lightTextSecondary = Color(0xFF6B6B76);

  // ── Общие сигнальные цвета ──────────────────────────────────────────
  /// Спокойный индиго — низкая мощность.
  static const Color accentLow = Color(0xFF6366F1);

  /// Кораллово-красный — пиковая интенсивность.
  static const Color accentHigh = Color(0xFFF43F5E);

  /// Приглушённый красный кнопки СТОП.
  static const Color stop = Color(0xFFDC2626);

  /// Истинный чёрный OLED-замка (ТЗ 3.2.4) — всегда чёрный.
  static const Color oledBlack = Color(0xFF000000);

  /// Динамический акцент: интерполяция от выбранного акцента к кораллу.
  static Color accentForIntensity(double u, {Color? from}) =>
      Color.lerp(from ?? accentLow, accentHigh, u.clamp(0.0, 1.0))!;
}

/// Набор цветов текущей вариации темы.
class NoctwaveColors {
  const NoctwaveColors({
    required this.background,
    required this.surface,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.brightness,
  });

  final Color background;
  final Color surface;
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;
  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  static const NoctwaveColors dark = NoctwaveColors(
    background: NoctwavePalette.background,
    surface: NoctwavePalette.surface,
    outline: NoctwavePalette.outline,
    textPrimary: NoctwavePalette.textPrimary,
    textSecondary: NoctwavePalette.textSecondary,
    brightness: Brightness.dark,
  );

  static const NoctwaveColors light = NoctwaveColors(
    background: NoctwavePalette.lightBackground,
    surface: NoctwavePalette.lightSurface,
    outline: NoctwavePalette.lightOutline,
    textPrimary: NoctwavePalette.lightTextPrimary,
    textSecondary: NoctwavePalette.lightTextSecondary,
    brightness: Brightness.light,
  );

  /// ThemeExtension для доступа к цветам из виджетов.
  static NoctwaveColors of(BuildContext context) {
    final ext = Theme.of(context).extension<NoctwaveThemeExtension>();
    if (ext != null) return ext.colors;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

class NoctwaveThemeExtension extends ThemeExtension<NoctwaveThemeExtension> {
  const NoctwaveThemeExtension(this.colors);

  final NoctwaveColors colors;

  @override
  NoctwaveThemeExtension copyWith({NoctwaveColors? colors}) =>
      NoctwaveThemeExtension(colors ?? this.colors);

  @override
  NoctwaveThemeExtension lerp(covariant NoctwaveThemeExtension? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

/// Строит тему для заданной вариации и акцентного цвета.
ThemeData buildNoctwaveTheme({
  NoctwaveColors colors = NoctwaveColors.dark,
  Color accent = NoctwavePalette.accentLow,
}) {
  final scheme = ColorScheme(
    brightness: colors.brightness,
    primary: accent,
    onPrimary: Colors.white,
    secondary: NoctwavePalette.accentHigh,
    onSecondary: Colors.white,
    error: NoctwavePalette.stop,
    onError: Colors.white,
    surface: colors.surface,
    onSurface: colors.textPrimary,
    outline: colors.outline,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: colors.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.background,
    dividerColor: colors.outline,
    extensions: <ThemeExtension<dynamic>>[NoctwaveThemeExtension(colors)],
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: colors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outline),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: accent.withValues(alpha: 0.25),
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(fontSize: 12, color: colors.textSecondary),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surface,
      selectedColor: accent.withValues(alpha: 0.3),
      side: BorderSide(color: colors.outline),
      labelStyle: TextStyle(color: colors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        color: colors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(color: colors.textPrimary),
      bodySmall: TextStyle(color: colors.textSecondary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.isDark ? colors.surface : colors.textPrimary,
      contentTextStyle: TextStyle(
        color: colors.isDark ? colors.textPrimary : colors.surface,
      ),
    ),
  );
}
