import 'package:material_ui/material_ui.dart';

/// OLED Dark дизайн-система (ТЗ 3.1).
abstract final class NoctwavePalette {
  /// Глубокий чёрный для OLED-матриц.
  static const Color background = Color(0xFF09090B);

  /// Карточки и поверхности.
  static const Color surface = Color(0xFF141418);

  /// Разделители и обводки.
  static const Color outline = Color(0xFF222228);

  /// Основной текст.
  static const Color textPrimary = Color(0xFFFAFAFA);

  /// Вторичный текст.
  static const Color textSecondary = Color(0xFFA1A1AA);

  /// Спокойный индиго — низкая мощность.
  static const Color accentLow = Color(0xFF6366F1);

  /// Кораллово-красный — пиковая интенсивность.
  static const Color accentHigh = Color(0xFFF43F5E);

  /// Приглушённый красный кнопки СТОП.
  static const Color stop = Color(0xFFDC2626);

  /// Истинный чёрный OLED-замка (ТЗ 3.2.4).
  static const Color oledBlack = Color(0xFF000000);

  /// Динамический акцент: интерполяция индиго → коралл по уровню мощности.
  static Color accentForIntensity(double u) =>
      Color.lerp(accentLow, accentHigh, u.clamp(0.0, 1.0))!;
}

/// Тёмная тема приложения — единственная (Dark-First, ТЗ 1.2).
ThemeData buildNoctwaveTheme() {
  const scheme = ColorScheme.dark(
    primary: NoctwavePalette.accentLow,
    onPrimary: NoctwavePalette.textPrimary,
    secondary: NoctwavePalette.accentHigh,
    onSecondary: NoctwavePalette.textPrimary,
    surface: NoctwavePalette.surface,
    onSurface: NoctwavePalette.textPrimary,
    error: NoctwavePalette.stop,
    onError: NoctwavePalette.textPrimary,
    outline: NoctwavePalette.outline,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: NoctwavePalette.background,
    canvasColor: NoctwavePalette.background,
    dividerColor: NoctwavePalette.outline,
    appBarTheme: const AppBarTheme(
      backgroundColor: NoctwavePalette.background,
      foregroundColor: NoctwavePalette.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: NoctwavePalette.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: NoctwavePalette.outline),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: NoctwavePalette.surface,
      indicatorColor: NoctwavePalette.accentLow.withValues(alpha: 0.25),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, color: NoctwavePalette.textSecondary),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: NoctwavePalette.surface,
      selectedColor: NoctwavePalette.accentLow.withValues(alpha: 0.3),
      side: const BorderSide(color: NoctwavePalette.outline),
      labelStyle: const TextStyle(color: NoctwavePalette.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NoctwavePalette.accentLow,
        foregroundColor: NoctwavePalette.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: NoctwavePalette.textPrimary,
        side: const BorderSide(color: NoctwavePalette.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        color: NoctwavePalette.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: NoctwavePalette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(color: NoctwavePalette.textPrimary),
      bodySmall: TextStyle(color: NoctwavePalette.textSecondary),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: NoctwavePalette.surface,
      contentTextStyle: TextStyle(color: NoctwavePalette.textPrimary),
    ),
  );
}
