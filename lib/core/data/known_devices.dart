/// Проверенные таблицы команд протокола LoveSpouse.
///
/// Источники: HCI-логи реальных устройств (fa-architect/mcontrol,
/// подтверждено на железе), OpenSpouse PROTOCOL.md, ТЗ 5.1.
///
/// Ключевые факты:
/// - Устройство помнит последнюю команду по каналу и работает, пока
///   получает broadcast; watchdog ~800–1000 мс — паузы требуют явного СТОП.
/// - 9 паттернов на канал + стоп (индекс 0).
/// - Семейства различаются префиксом; команды внутри семейства общие.
library;

import '../models/device_profile.dart';

/// Семейство устройств: префикс + проверенные каналы.
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

/// Известные семейства с проверенными командами.
abstract final class KnownDevices {
  // ── Семейство 6DB643CE97FE427C (barcode 3711 и совместимые) ─────────
  // Команды из HCI-логов mcontrol (Pixel 6a, подтверждено на железе)
  // и OpenSpouse PROTOCOL.md. 9 паттернов + стоп на канал.

  /// Общий канал «Всё» (оба мотора сразу).
  static const List<String> allSteps = <String>[
    'E5157D', // 0 стоп
    'E49C6C', // 1
    'E7076D', // 2
    'E68E4F', // 3
    'E13579', // 4
    'E0BC68', // 5
    'E3275A', // 6
    'E2AE4B', // 7
    'ED59B3', // 8
    'ECD0A2', // 9
  ];

  /// Канал «Толчки» (CH1, stroke).
  static const List<String> strokeSteps = <String>[
    'D5964C', // 0 стоп
    'D41F5D', // 1
    'D7846F', // 2
    'D60D7E', // 3
    'D1B20A', // 4
    'D03B1B', // 5
    'D3A029', // 6
    'D22938', // 7
    'DDDEC0', // 8
    'DC57D1', // 9
  ];

  /// Канал «Вибрация» (CH2, vibe).
  static const List<String> vibeSteps = <String>[
    'A5113F', // 0 стоп
    'A4982E', // 1
    'A7031C', // 2
    'A68A0D', // 3
    'A13579', // 4
    'A0BC68', // 5
    'A3275A', // 6
    'A2AE4B', // 7
    'AD59B3', // 8
    'ACD0A2', // 9
  ];

  static List<PresetCommand> _presets(List<String> steps) => <PresetCommand>[
        for (var i = 1; i < steps.length; i++)
          PresetCommand(
            id: 'p$i',
            label: 'Паттерн $i',
            cmdHex: steps[i],
            icon: 'speed_$i',
          ),
      ];

  /// Двухканальное устройство 6DB643CE97FE427C (толчки + вибрация).
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

  /// Одноканальное устройство того же семейства (общий канал).
  static DeviceFamily singleMotor() => DeviceFamily(
        id: 'single-6db6',
        name: 'Один мотор (9 паттернов)',
        prefixHex: '6DB643CE97FE427C',
        note: 'Команды общего канала из OpenSpouse PROTOCOL.md.',
        channels: <DeviceChannel>[
          DeviceChannel(
            id: 'ch_all',
            name: 'Вибрация',
            type: ChannelType.vibrate,
            stopCmdHex: allSteps.first,
            intensityStepsHex: allSteps,
            presets: _presets(allSteps),
          ),
        ],
      );

  // ── Семейство wbMSE (77624D5345, barcode 4923 и др.) ────────────────
  // Префикс из живого ответа zlmicro API для barcode 4923.
  // Команды этого семейства отличаются от 6DB6; для точных значений
  // нужен HCI-лог или Command Hunter. Базовый стоп и режим 1 известны
  // из открытых контроллеров (love-spouse-controller: STOP=0x00,
  // MODE1=0x01 в сыром виде до скремблирования).

  static DeviceFamily wbMse() => DeviceFamily(
        id: 'wbmse-4923',
        name: 'wbMSE (barcode 4923, AAGS079)',
        prefixHex: '77624D5345',
        note: 'Префикс из API. Команды уточняются через Command Hunter — '
            'семейство использует иное скремблирование.',
        channels: <DeviceChannel>[
          DeviceChannel(
            id: 'ch_1',
            name: 'Мотор 1',
            type: ChannelType.vibrate,
            stopCmdHex: allSteps.first,
            intensityStepsHex: allSteps,
            presets: _presets(allSteps),
          ),
          DeviceChannel(
            id: 'ch_2',
            name: 'Мотор 2',
            type: ChannelType.vibrate,
            stopCmdHex: allSteps.first,
            intensityStepsHex: allSteps,
            presets: _presets(allSteps),
          ),
        ],
      );

  /// Все известные семейства.
  static List<DeviceFamily> all() => <DeviceFamily>[
        dualMotor(),
        singleMotor(),
        wbMse(),
      ];

  /// Находит семейство по префиксу (нормализованный HEX).
  static DeviceFamily? byPrefix(String prefixHex) {
    final normalized = prefixHex.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
    for (final family in all()) {
      if (family.prefixHex == normalized) return family;
    }
    return null;
  }
}
