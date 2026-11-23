import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noctwave_app/features/profile/color_picker_dialog.dart';

void main() {
  testWidgets('Пикер цвета открывается и применяет выбранный цвет',
      (WidgetTester tester) async {
    Color? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showColorPicker(context, const Color(0xFF6366F1));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Свой цвет'), findsOneWidget);
    expect(find.text('HEX'), findsOneWidget);

    // Вводим HEX и применяем.
    await tester.enterText(find.byType(TextField), '14B8A6');
    await tester.pump();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.toARGB32() & 0xFFFFFF, 0x14B8A6);
  });
}
