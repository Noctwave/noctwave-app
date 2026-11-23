/// Проверенные таблицы команд протокола LoveSpouse (BroadLink Fastcon).
///
/// Источники: живой ответ zlmicro API (barcode 4923), RfPayloadEncoder
/// (порт love-spouse-controller, MIT), HCI-логи mcontrol, OpenSpouse.
///
/// Ключевой факт: сырой 5-байтовый префикс из API (wbMSE = 77 62 4d 53 45)
/// прогоняется через get_rf_payload и даёт эфирный префикс
/// 6DB643CE97FE427C. Команды — однобайтовые: 0x00 стоп, 0x01–0x09 паттерны.
library;

import '../ble/rf_payload_encoder.dart';
import '../models/device_profile.dart';

/// Семейство устройств: эфирный префикс + проверенные каналы.
class DeviceFamily {
  const DeviceFamily({
    required this.id,
    required this.name,
    required this.prefixHex,
    required this.channels,
    this.manufacturerId = 0xFFF0,
    this.note,
  });

  final String id;
  final String name;
  final String prefixHex;
  final int manufacturerId;
  final List<DeviceChannel> channels;
  final String? note;
}

abstract final class KnownDevices {
  /// Сырой префикс семейства wbMSE из API (ASCII "wbMSE").
  static const List<int> rawWbMse = <int>[0x77, 0x62, 0x4D, 0x53, 0x45];

  /// Эфирные команды общего канала, посчитанные RfPayloadEncoder
  /// из сырых 0x00–0x09 (контрольный вектор сверен с ТЗ).
  static const List<String> allSteps = <String>[
    'E5157D', // 0x00 стоп
    'E49C6C', // 0x01
    'E7075E', // 0x02
    'E68E4F', // 0x03
    'E1313B', // 0x04
    'E0B82A', // 0x05
    'E32318', // 0x06
    'E2AA09', // 0x07
    'ED5DF1', // 0x08
    'ECD4E0', // 0x09
  ];

  /// Канал «Толчки» (CH1) — HCI-логи mcontrol.
  static const List<String> strokeSteps = <String>[
    'D5964C', 'D41F5D', 'D7846F', 'D60D7E', 'D1B20A',
    'D03B1B', 'D3A029', 'D22938', 'DDDEC0', 'DC57D1',
  ];

  /// Канал «Вибрация» (CH2) — HCI-логи mcontrol.
  static const List<String> vibeSteps = <String>[
    'A5113F', 'A4982E', 'A7031C', 'A68A0D', 'A13579',
    'A0BC68', 'A3275A', 'A2AE4B', 'AD59B3', 'ACD0A2',
  ];

  static List<PresetCommand> _presets(List<String> steps) => <PresetCommand>[
        for (var i = 1; i < steps.length; i++)
          PresetCommand(
            id: 'p$i',
            label: 'Режим $i',
            cmdHex: steps[i],
            icon: 'speed_$i',
          ),
      ];

  /// Строит каналы из сырого префикса API на лету (get_rf_payload).
  /// Работает для любого семейства, включая редкие модели и клоны.
  static List<DeviceChannel> channelsFromRawPrefix(List<int> raw) {
    String cmd(int rawByte) {
      final bytes = RfPayloadEncoder.encodeCommand(raw, rawByte);
      return bytes
          .sublist(8)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join();
    }

    final steps = <String>[for (var i = 0; i <= 9; i++) cmd(i)];
    return <DeviceChannel>[
      DeviceChannel(
        id: 'ch_1',
        name: 'Мотор 1',
        type: ChannelType.vibrate,
        stopCmdHex: steps.first,
        intensityStepsHex: steps,
        presets: _presets(steps),
      ),
    ];
  }

  /// Двухканальное устройство (толчки + вибрация), эфирный префикс.
  static DeviceFamily dualMotor() => DeviceFamily(
        id: 'dual-6db6',
        name: 'Два мотора (толчки + вибрация)',
        prefixHex: '6DB643CE97FE427C',
        note: 'Проверено на железе (HCI-логи). Каналы независимы.',
        channels: <DeviceChannel>[
          DeviceChannel(
            id: 'ch_stroke',
            name: 'Толчки',
            type: ChannelType.vibrate,
            stopCmdHex: strokeSteps.first,
            intensityStepsHex: strokeSteps,
            presets: _presets(strokeSteps),
          ),
          DeviceChannel(
            id: 'ch_vibe',
            name: 'Вибрация',
            type: ChannelType.vibrate,
            stopCmdHex: vibeSteps.first,
            intensityStepsHex: vibeSteps,
            presets: _presets(vibeSteps),
          ),
        ],
      );

  /// Одноканальное устройство массового семейства (9 паттернов).
  static DeviceFamily singleMotor() => DeviceFamily(
        id: 'single-6db6',
        name: 'Один мотор (9 паттернов)',
        prefixHex: '6DB643CE97FE427C',
        note: 'Команды посчитаны из сырых 0x00–0x09 (Fastcon).',
        channels: channelsFromRawPrefix(rawWbMse),
      );

  /// Все известные семейства для оффлайн-базы.
  static List<DeviceFamily> all() => <DeviceFamily>[
        singleMotor(),
        dualMotor(),
      ];

  /// Находит семейство по эфирному префиксу.
  static DeviceFamily? byPrefix(String prefixHex) {
    final normalized =
        prefixHex.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
    for (final family in all()) {
      if (family.prefixHex == normalized) return family;
    }
    return null;
  }
}
