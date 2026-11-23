import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/ble/love_spouse_codec.dart';

void main() {
  group('LoveSpouseCodec — контрольный вектор ТЗ 5.3', () {
    // Обязательный unit-тест из ТЗ:
    // prefix = 6D B6 43 CE 97 FE 42 7C, command = E5 15 7D (СТОП)
    const prefix = '6DB643CE97FE427C';
    const stopCommand = 'E5157D';

    test('сырой пейлоад — 11 байт', () {
      final raw = LoveSpouseCodec.rawPayload(prefix, stopCommand);
      expect(raw.length, 11);
      expect(LoveSpouseCodec.toHex(raw), '6DB643CE97FE427CE5157D');
    });

    test('XOR pre-whitening + терминатор 0x0B', () {
      final raw = LoveSpouseCodec.rawPayload(prefix, stopCommand);
      final whitened = LoveSpouseCodec.encodeWhitened(raw);
      expect(whitened.length, 12);
      expect(
        LoveSpouseCodec.toHex(whitened),
        'F9084923AECBC1D16E9C3D0B',
      );
    });

    test('шесть CBUUID совпадают с эталоном ТЗ', () {
      final uuids = LoveSpouseCodec.encodeIosUuids(prefix, stopCommand);
      expect(uuids, <String>[
        '08F9', '2349', 'CBAE', 'D1C1', '9C6E', '0B3D',
      ]);
    });

    test('порядок UUID строго сохраняется (Array, не Set)', () {
      final uuids = LoveSpouseCodec.encodeIosUuids(prefix, 'E49C6C');
      expect(uuids.length, 6);
      // Первая пара зависит только от префикса — стабильна для любой команды.
      expect(uuids.first, '08F9');
    });
  });

  group('LoveSpouseCodec — валидация', () {
    test('префикс не 8 байт → FormatException', () {
      expect(
        () => LoveSpouseCodec.rawPayload('AABB', 'E5157D'),
        throwsFormatException,
      );
    });

    test('команда не 3 байта → FormatException', () {
      expect(
        () => LoveSpouseCodec.rawPayload('6DB643CE97FE427C', 'E5'),
        throwsFormatException,
      );
    });

    test('нечётный HEX → FormatException', () {
      expect(() => LoveSpouseCodec.parseHex('ABC'), throwsFormatException);
    });

    test('регистр HEX не важен', () {
      final lower = LoveSpouseCodec.encodeIosUuids(
        '6db643ce97fe427c', 'e5157d',
      );
      final upper = LoveSpouseCodec.encodeIosUuids(
        '6DB643CE97FE427C', 'E5157D',
      );
      expect(lower, upper);
    });

    test('preview содержит rawHex, whitenedHex и iosServiceUuids', () {
      final preview =
          LoveSpouseCodec.preview('6DB643CE97FE427C', 'E5157D');
      expect(preview['rawHex'], '6DB643CE97FE427CE5157D');
      expect(preview['whitenedHex'], 'F9084923AECBC1D16E9C3D0B');
      expect(preview['iosServiceUuids'], <String>[
        '08F9', '2349', 'CBAE', 'D1C1', '9C6E', '0B3D',
      ]);
    });
  });
}
