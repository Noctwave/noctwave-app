import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctwave_app/core/theme/noctwave_theme.dart';

void main() {
  group('Тема — акцентный цвет', () {
    test('secondary равен акценту (SegmentedButton выделяет выбранный)', () {
      const accent = Color(0xFF14B8A6);
      final theme = buildNoctwaveTheme(accent: accent);
      expect(theme.colorScheme.primary, accent);
      expect(theme.colorScheme.secondary, accent);
    });

    test('segmentedButtonTheme: выбранный вариант окрашен акцентом', () {
      const accent = Color(0xFFF59E0B);
      final theme = buildNoctwaveTheme(accent: accent);
      final style = theme.segmentedButtonTheme.style!;
      final selectedBg = style.backgroundColor!
          .resolve(<WidgetState>{WidgetState.selected});
      final selectedFg = style.foregroundColor!
          .resolve(<WidgetState>{WidgetState.selected});
      expect(selectedFg, accent);
      expect(selectedBg, accent.withValues(alpha: 0.25));
    });

    test('светлая и тёмная вариации различаются поверхностями', () {
      final dark = buildNoctwaveTheme(colors: NoctwaveColors.dark);
      final light = buildNoctwaveTheme(colors: NoctwaveColors.light);
      expect(dark.scaffoldBackgroundColor, isNot(light.scaffoldBackgroundColor));
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
    });
  });
}
