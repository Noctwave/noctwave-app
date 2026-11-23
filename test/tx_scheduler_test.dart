import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/ble/ble_advertiser.dart';
import 'package:noctwave_app/core/ble/tx_scheduler.dart';

void main() {
  const prefix = '6DB643CE97FE427C';
  const stopCmd = 'E5157D';
  const steps = <String>['E5157D', 'F41D7C', 'F7864E', 'E68E4F'];

  group('TxScheduler.quantize (ТЗ 5.4.1)', () {
    test('u = 0 → стоп-команда', () {
      expect(
        TxScheduler.quantize(u: 0, intensityStepsHex: steps, stopCmdHex: stopCmd),
        stopCmd,
      );
    });

    test('u = 1 → последняя ступень', () {
      expect(
        TxScheduler.quantize(u: 1, intensityStepsHex: steps, stopCmdHex: stopCmd),
        'E68E4F',
      );
    });

    test('u = 0.5 → round(0.5 * 3) = 2 → F7864E', () {
      expect(
        TxScheduler.quantize(u: 0.5, intensityStepsHex: steps, stopCmdHex: stopCmd),
        'F7864E',
      );
    });

    test('u вне [0,1] клампится', () {
      expect(
        TxScheduler.quantize(u: -3, intensityStepsHex: steps, stopCmdHex: stopCmd),
        stopCmd,
      );
      expect(
        TxScheduler.quantize(u: 7, intensityStepsHex: steps, stopCmdHex: stopCmd),
        'E68E4F',
      );
    });

    test('пустые ступени → ArgumentError', () {
      expect(
        () => TxScheduler.quantize(
          u: 0.5, intensityStepsHex: const <String>[], stopCmdHex: stopCmd,
        ),
        throwsArgumentError,
      );
    });
  });

  group('TxScheduler — дедупликация и троттлинг (ТЗ 5.4.2)', () {
    test('повторный тот же HEX не перезапускает рекламу', () async {
      final gateway = InMemoryBleAdvertiser();
      var now = 1000;
      final scheduler = TxScheduler(
        gateway: gateway,
        currentTimeMs: () => now,
      );

      await scheduler.updateDynamicCommand(
        prefixHex: prefix, commandHex: 'F41D7C', manufacturerId: 0xFFF0,
      );
      now += 500;
      await scheduler.updateDynamicCommand(
        prefixHex: prefix, commandHex: 'F41D7C', manufacturerId: 0xFFF0,
      );

      final broadcasts =
          gateway.calls.where((c) => c['method'] == 'broadcastCommand').toList();
      expect(broadcasts.length, 1);
      await scheduler.dispose();
    });

    test('смена HEX сразу после отправки откладывается до minTxIntervalMs',
        () async {
      final gateway = InMemoryBleAdvertiser();
      var now = 1000;
      final scheduler = TxScheduler(
        gateway: gateway,
        config: const TxSchedulerConfig(minTxIntervalMs: 180),
        currentTimeMs: () => now,
      );

      await scheduler.updateDynamicCommand(
        prefixHex: prefix, commandHex: 'F41D7C', manufacturerId: 0xFFF0,
      );
      now += 50; // прошло только 50 мс
      final pending = scheduler.updateDynamicCommand(
        prefixHex: prefix, commandHex: 'F7864E', manufacturerId: 0xFFF0,
      );
      // До истечения интервала вторая команда ещё не отправлена.
      await Future<void>.delayed(Duration.zero);
      var broadcasts =
          gateway.calls.where((c) => c['method'] == 'broadcastCommand').toList();
      expect(broadcasts.length, 1);

      await pending; // ждём троттлинг-задержку (130 мс реального времени)
      broadcasts =
          gateway.calls.where((c) => c['method'] == 'broadcastCommand').toList();
      expect(broadcasts.length, 2);
      expect(broadcasts.last['commandHex'], 'F7864E');
      await scheduler.dispose();
    });

    test('после паузы дольше интервала отправка немедленная', () async {
      final gateway = InMemoryBleAdvertiser();
      var now = 1000;
      final scheduler = TxScheduler(
        gateway: gateway,
        currentTimeMs: () => now,
      );

      await scheduler.updateDynamicCommand(
        prefixHex: prefix, commandHex: 'F41D7C', manufacturerId: 0xFFF0,
      );
      now += 1000;
      await scheduler.updateDynamicCommand(
        prefixHex: prefix, commandHex: 'F7864E', manufacturerId: 0xFFF0,
      );

      final broadcasts =
          gateway.calls.where((c) => c['method'] == 'broadcastCommand').toList();
      expect(broadcasts.length, 2);
      expect(broadcasts.last['durationMs'], 0);
      await scheduler.dispose();
    });
  });

  group('TxScheduler — burst и приоритетный СТОП (ТЗ 5.4.3–5.4.4)', () {
    test('одиночная команда вещается burst-окном 350 мс', () async {
      final gateway = InMemoryBleAdvertiser();
      final scheduler = TxScheduler(gateway: gateway);

      await scheduler.sendBurstCommand(
        prefixHex: prefix, commandHex: 'F41D7C', manufacturerId: 0xFFF0,
      );

      expect(gateway.calls.single['method'], 'broadcastCommand');
      expect(gateway.calls.single['durationMs'], 350);
      expect(scheduler.isBurstActive, isTrue);
      await scheduler.dispose();
    });

    test('СТОП отменяет отложенную динамическую команду', () async {
      final gateway = InMemoryBleAdvertiser();
      var now = 1000;
      final scheduler = TxScheduler(
        gateway: gateway,
        currentTimeMs: () => now,
      );

      await scheduler.updateDynamicCommand(
        prefixHex: prefix, commandHex: 'F41D7C', manufacturerId: 0xFFF0,
      );
      now += 10;
      final throttled = scheduler.updateDynamicCommand(
        prefixHex: prefix, commandHex: 'F7864E', manufacturerId: 0xFFF0,
      );
      // Приоритетный СТОП, пока вторая команда ждёт троттлинг.
      await scheduler.stop(
        prefixHex: prefix, stopCmdHex: stopCmd, manufacturerId: 0xFFF0,
      );
      await throttled;

      final stopCalls =
          gateway.calls.where((c) => c['method'] == 'broadcastStop').toList();
      expect(stopCalls.length, 1);
      expect(stopCalls.single['durationMs'], 700);
      // Отложенная F7864E не должна была уйти в эфир после СТОП.
      final broadcasts =
          gateway.calls.where((c) => c['method'] == 'broadcastCommand').toList();
      expect(broadcasts.map((c) => c['commandHex']), isNot(contains('F7864E')));
      await scheduler.dispose();
    });

    test('dispose выключает рекламу', () async {
      final gateway = InMemoryBleAdvertiser();
      final scheduler = TxScheduler(gateway: gateway);
      await scheduler.sendBurstCommand(
        prefixHex: prefix, commandHex: 'F41D7C', manufacturerId: 0xFFF0,
      );
      await scheduler.dispose();
      expect(
        gateway.calls.last['method'],
        'stopAdvertising',
      );
    });
  });
}
