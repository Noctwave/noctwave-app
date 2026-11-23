import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/ble/ble_advertiser.dart';
import 'package:noctwave_app/core/ble/channel_mixer.dart';

void main() {
  const prefix = '6DB643CE97FE427C';

  group('ChannelMixer — поканальная ротация без сброса моторов', () {
    test('setCommand запускает непрерывную передачу', () async {
      final gateway = InMemoryBleAdvertiser();
      final mixer = ChannelMixer(
        gateway: gateway, prefixHex: prefix, manufacturerId: 0xFFF0, tickMs: 20,
      );
      mixer.registerStop('ch1', 'E5157D');
      mixer.setCommand('ch1', 'E49C6C');
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(mixer.isRunning, isTrue);
      final cmds = gateway.calls
          .where((c) => c['method'] == 'broadcastCommand')
          .toList();
      expect(cmds, isNotEmpty);
      expect(cmds.first['commandHex'], 'E49C6C');
      await mixer.dispose();
    });

    test('два канала чередуются, переключение не сбрасывает первый', () async {
      final gateway = InMemoryBleAdvertiser();
      final mixer = ChannelMixer(
        gateway: gateway, prefixHex: prefix, manufacturerId: 0xFFF0, tickMs: 20,
      );
      mixer.registerStop('ch1', 'D5964C');
      mixer.registerStop('ch2', 'A5113F');
      mixer.setCommand('ch1', 'D41F5D');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Включаем второй мотор — первый НЕ должен получить стоп.
      mixer.setCommand('ch2', 'A4982E');
      await Future<void>.delayed(const Duration(milliseconds: 90));
      final cmds = gateway.calls
          .where((c) => c['method'] == 'broadcastCommand')
          .map((c) => c['commandHex'])
          .toList();
      expect(cmds, contains('D41F5D'));
      expect(cmds, contains('A4982E'));
      final stops = gateway.calls
          .where((c) => c['method'] == 'broadcastStop')
          .toList();
      expect(stops, isEmpty); // никакого сброса при переключении
      await mixer.dispose();
    });

    test('stopAll шлёт стоп каждого канала и гасит ротацию', () async {
      final gateway = InMemoryBleAdvertiser();
      final mixer = ChannelMixer(
        gateway: gateway, prefixHex: prefix, manufacturerId: 0xFFF0, tickMs: 20,
      );
      mixer.registerStop('ch1', 'D5964C');
      mixer.registerStop('ch2', 'A5113F');
      mixer.setCommand('ch1', 'D41F5D');
      mixer.setCommand('ch2', 'A4982E');
      await mixer.stopAll();
      expect(mixer.isRunning, isFalse);
      final stops = gateway.calls
          .where((c) => c['method'] == 'broadcastStop')
          .map((c) => c['stopHex'])
          .toSet();
      expect(stops, containsAll(<String>['D5964C', 'A5113F']));
      await mixer.dispose();
    });
  });
}
