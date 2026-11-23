import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/ble/ble_advertiser.dart';
import 'package:noctwave_app/core/models/device_profile.dart';
import 'package:noctwave_app/features/control/control_page.dart';

void main() {
  const demoDevice = DeviceProfile(
    id: 'demo-1',
    name: 'Модель #4923',
    broadcastPrefixHex: '6DB643CE97FE427C',
    manufacturerId: 65520,
    channels: <DeviceChannel>[
      DeviceChannel(
        id: 'ch_vibe',
        name: 'Вибрация',
        type: ChannelType.vibrate,
        stopCmdHex: 'E5157D',
        intensityStepsHex: <String>['E5157D', 'F41D7C', 'F7864E', 'E68E4F'],
        presets: <PresetCommand>[
          PresetCommand(id: 'p1', label: 'Слабо', cmdHex: 'F41D7C'),
        ],
      ),
    ],
  );

  testWidgets('Экран управления рисует док TX · REC · СТОП и плитки режимов',
      (WidgetTester tester) async {
    final gateway = _NoopGateway();
    await tester.pumpWidget(
      MaterialApp(home: ControlPage(device: demoDevice, gateway: gateway)),
    );

    expect(find.text('REC'), findsOneWidget);
    expect(find.text('СТОП'), findsOneWidget);
    expect(find.text('TX'), findsOneWidget);
    expect(find.text('Удерживай — максимум'), findsOneWidget);
    expect(find.text('Слабо'), findsOneWidget);
  });

  testWidgets('Экран управления без каналов показывает заглушку',
      (WidgetTester tester) async {
    const emptyDevice = DeviceProfile(
      id: 'demo-2',
      name: 'Пустое',
      broadcastPrefixHex: '6DB643CE97FE427C',
      manufacturerId: 65520,
      channels: <DeviceChannel>[],
    );
    await tester.pumpWidget(MaterialApp(
      home: ControlPage(device: emptyDevice, gateway: _NoopGateway()),
    ));
    expect(find.text('У устройства нет каналов'), findsOneWidget);
  });
}

/// Заглушка-шлюз для widget-тестов: не трогает MethodChannel.
class _NoopGateway implements BleAdvertiserGateway {
  @override
  Future<void> broadcastCommand({
    required String prefixHex,
    required String commandHex,
    required int manufacturerId,
    required int durationMs,
  }) async {}

  @override
  Future<void> broadcastStop({
    required String prefixHex,
    required String stopHex,
    required int manufacturerId,
    required int durationMs,
  }) async {}

  @override
  Future<BluetoothAdapterState> getBluetoothState() async =>
      BluetoothAdapterState.ready;

  @override
  Future<Map<String, Object>> previewEncodedPacket({
    required String prefixHex,
    required String commandHex,
  }) async => const <String, Object>{};

  @override
  Future<void> stopAdvertising() async {}
}
