import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/ble/tx_log.dart';
import 'package:noctwave_app/core/storage/local_store.dart';

void main() {
  group('TxLog — ring-buffer только в RAM (ТЗ 4.6.3 / 8.5)', () {
    test('хранит не более capacity записей', () {
      final log = TxLog(capacity: 5);
      for (var i = 0; i < 8; i++) {
        log.add(TxLogEntry(
          timestamp: DateTime.now(),
          prefixHex: '6DB643CE97FE427C',
          commandHex: 'F41D7C',
          isStop: false,
          durationMs: 350,
        ));
      }
      expect(log.length, 5);
    });

    test('entries отдаёт новые сверху', () {
      final log = TxLog();
      log.add(TxLogEntry(
        timestamp: DateTime.now(),
        prefixHex: '6DB643CE97FE427C',
        commandHex: 'F41D7C',
        isStop: false,
        durationMs: 350,
      ));
      log.add(TxLogEntry(
        timestamp: DateTime.now(),
        prefixHex: '6DB643CE97FE427C',
        commandHex: 'E5157D',
        isStop: true,
        durationMs: 700,
      ));
      expect(log.entries.first.commandHex, 'E5157D');
      expect(log.entries.first.rawHex, '6DB643CE97FE427CE5157D');
      expect(log.entries.first.iosServiceUuids,
          <String>['08F9', '2349', 'CBAE', 'D1C1', '9C6E', '0B3D']);
    });

    test('уведомляет слушателей и очищается', () {
      final log = TxLog();
      var notified = 0;
      log.addListener(() => notified++);
      log.add(TxLogEntry(
        timestamp: DateTime.now(),
        prefixHex: '6DB643CE97FE427C',
        commandHex: 'F41D7C',
        isStop: false,
        durationMs: 350,
      ));
      expect(notified, 1);
      log.clear();
      expect(notified, 2);
      expect(log.length, 0);
    });

    test('ёмкость по умолчанию 200 (ТЗ 8.5)', () {
      expect(TxLog().capacity, 200);
    });
  });

  group('AppSettings — сериализация и copyWith', () {
    test('round-trip JSON не теряет поля', () {
      const settings = AppSettings(
        hapticsEnabled: false,
        volumeDownStop: false,
        debugModeEnabled: true,
        burstDurationMs: 400,
        minTxIntervalMs: 200,
        biometricUnlock: true,
        themeMode: 'light',
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.hapticsEnabled, false);
      expect(restored.volumeDownStop, false);
      expect(restored.debugModeEnabled, true);
      expect(restored.burstDurationMs, 400);
      expect(restored.minTxIntervalMs, 200);
      expect(restored.biometricUnlock, true);
      expect(restored.themeMode, 'light');
    });

    test('copyWith сбрасывает PIN через clearPinHash', () {
      const settings = AppSettings(appPinHash: 'abc');
      final cleared = settings.copyWith(clearPinHash: true);
      expect(cleared.appPinHash, isNull);
    });

    test('defaults соответствуют ТЗ (350/700/180)', () {
      const settings = AppSettings();
      expect(settings.burstDurationMs, 350);
      expect(settings.stopBurstDurationMs, 700);
      expect(settings.minTxIntervalMs, 180);
      expect(settings.hapticsEnabled, isTrue);
    });
  });
}
