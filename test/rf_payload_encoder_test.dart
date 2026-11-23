import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/ble/rf_payload_encoder.dart';

void main() {
  const wbMse = <int>[0x77, 0x62, 0x4D, 0x53, 0x45];

  String hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join();

  test('контрольный вектор: wbMSE + 0x00 → эталонный стоп-пакет ТЗ', () {
    final out = RfPayloadEncoder.encodeCommand(wbMse, 0x00);
    expect(hex(out), '6DB643CE97FE427CE5157D');
  });

  test('wbMSE + 0x01 → режим 1 (E49C6C)', () {
    final out = RfPayloadEncoder.encodeCommand(wbMse, 0x01);
    expect(hex(out).substring(16), 'E49C6C');
  });

  test('airPrefixHex(wbMSE) = 6DB643CE97FE427C', () {
    expect(RfPayloadEncoder.airPrefixHex(wbMse), '6DB643CE97FE427C');
  });

  test('карта сырых команд 0x00..0x2F (для сверки с таблицами)', () {
    // ignore: avoid_print
    for (var c = 0x00; c <= 0x2F; c++) {
      final out = RfPayloadEncoder.encodeCommand(wbMse, c);
      // ignore: avoid_print
      print('0x${c.toRadixString(16).padLeft(2, '0')} -> ${hex(out).substring(16)}');
    }
  });
}
