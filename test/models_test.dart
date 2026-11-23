import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/models/device_profile.dart';

void main() {
  group('DeviceProfile — сериализация по схеме ТЗ 6.2', () {
    const profileJson = <String, dynamic>{
      'id': 'test-uuid',
      'barcode': '4923',
      'name': 'Модель #4923',
      'localImagePath': 'devices/4923.png',
      'broadcastPrefixHex': '6DB643CE97FE427C',
      'manufacturerId': 65520,
      'channels': <dynamic>[
        <String, dynamic>{
          'id': 'ch_vibe',
          'name': 'Вибрация',
          'type': 'vibrate',
          'stopCmdHex': 'E5157D',
          'intensityStepsHex': <String>[
            'E5157D', 'F41D7C', 'F7864E', 'E68E4F',
          ],
          'presets': <dynamic>[
            <String, dynamic>{
              'id': 'p1',
              'label': 'Слабо',
              'cmdHex': 'F41D7C',
              'icon': 'speed_1',
              'isCustom': false,
            },
          ],
        },
      ],
      'createdAt': '2026-11-23T12:00:00Z',
    };

    test('fromJson читает эталонную модель из ТЗ', () {
      final profile = DeviceProfile.fromJson(profileJson);
      expect(profile.id, 'test-uuid');
      expect(profile.barcode, '4923');
      expect(profile.broadcastPrefixHex, '6DB643CE97FE427C');
      expect(profile.manufacturerId, 65520);
      expect(profile.channels.single.intensityStepsHex.length, 4);
      expect(profile.channels.single.presets.single.label, 'Слабо');
      expect(profile.primaryChannel?.id, 'ch_vibe');
    });

    test('round-trip JSON не теряет данные', () {
      final profile = DeviceProfile.fromJson(profileJson);
      final restored = DeviceProfile.fromJson(profile.toJson());
      expect(restored.toJson(), profile.toJson());
    });
  });

  group('RecordedPattern — ТЗ 6.2', () {
    test('события ритма сериализуются без потерь', () {
      const patternJson = <String, dynamic>{
        'id': 'p-uuid',
        'name': 'Медленная волна',
        'deviceId': 'test-uuid',
        'durationMs': 14200,
        'events': <dynamic>[
          <String, dynamic>{
            'atMs': 0, 'channelId': 'ch_vibe', 'cmdHex': 'F41D7C',
          },
          <String, dynamic>{
            'atMs': 1500, 'channelId': 'ch_vibe', 'cmdHex': 'F7864E',
          },
          <String, dynamic>{
            'atMs': 3200, 'channelId': 'ch_vibe', 'cmdHex': 'E5157D',
          },
        ],
      };
      final pattern = RecordedPattern.fromJson(patternJson);
      expect(pattern.events.length, 3);
      expect(pattern.events[1].atMs, 1500);
      final restored = RecordedPattern.fromJson(pattern.toJson());
      expect(restored.toJson(), pattern.toJson());
    });
  });

  group('AppBackup — экспорт/импорт базы (ТЗ 3.2.5)', () {
    test('encode → decode восстанавливает устройства и ритмы', () {
      final backup = AppBackup(
        version: AppBackup.schemaVersion,
        devices: <DeviceProfile>[
          DeviceProfile.fromJson(const <String, dynamic>{
            'id': 'd1',
            'name': 'Тест',
            'broadcastPrefixHex': '6DB643CE97FE427C',
            'channels': <dynamic>[],
          }),
        ],
        patterns: <RecordedPattern>[
          RecordedPattern.fromJson(const <String, dynamic>{
            'id': 'r1',
            'name': 'Волна',
            'deviceId': 'd1',
            'durationMs': 1000,
            'events': <dynamic>[],
          }),
        ],
      );
      final restored = AppBackup.decode(backup.encode());
      expect(restored.devices.length, 1);
      expect(restored.patterns.length, 1);
      expect(restored.devices.single.id, 'd1');
      expect(restored.version, AppBackup.schemaVersion);
    });
  });
}
