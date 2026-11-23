import 'dart:convert';

/// Тип канала устройства (ТЗ 6.2).
enum ChannelType { vibrate, rotate, heat, vacuum, pump, generic }

/// Пресет режима: базовая скорость, штатный паттерн прошивки или
/// пользовательская команда, найденная через Command Hunter (ТЗ 4.6.1).
class PresetCommand {
  const PresetCommand({
    required this.id,
    required this.label,
    required this.cmdHex,
    this.icon = 'spark',
    this.isCustom = false,
  });

  final String id;
  final String label;
  final String cmdHex;
  final String icon;
  final bool isCustom;

  factory PresetCommand.fromJson(Map<String, dynamic> json) => PresetCommand(
        id: json['id'] as String,
        label: json['label'] as String,
        cmdHex: json['cmdHex'] as String,
        icon: (json['icon'] as String?) ?? 'spark',
        isCustom: (json['isCustom'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'cmdHex': cmdHex,
        'icon': icon,
        'isCustom': isCustom,
      };
}

/// Канал устройства: ступени интенсивности и набор пресетов (ТЗ 6.2).
class DeviceChannel {
  const DeviceChannel({
    required this.id,
    required this.name,
    required this.type,
    required this.stopCmdHex,
    required this.intensityStepsHex,
    this.presets = const <PresetCommand>[],
  });

  final String id;
  final String name;
  final ChannelType type;
  final String stopCmdHex;

  /// Ступени интенсивности; индекс 0 обязан совпадать со [stopCmdHex]
  /// (квантование u = 0 → стоп, ТЗ 5.4.1).
  final List<String> intensityStepsHex;
  final List<PresetCommand> presets;

  factory DeviceChannel.fromJson(Map<String, dynamic> json) => DeviceChannel(
        id: json['id'] as String,
        name: json['name'] as String,
        type: ChannelType.values.firstWhere(
          (t) => t.name == (json['type'] as String? ?? 'vibrate'),
          orElse: () => ChannelType.vibrate,
        ),
        stopCmdHex: json['stopCmdHex'] as String,
        intensityStepsHex:
            (json['intensityStepsHex'] as List<dynamic>).cast<String>(),
        presets: ((json['presets'] as List<dynamic>?) ?? <dynamic>[])
            .map((e) => PresetCommand.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'type': type.name,
        'stopCmdHex': stopCmdHex,
        'intensityStepsHex': intensityStepsHex,
        'presets': presets.map((p) => p.toJson()).toList(),
      };
}

/// Профиль устройства (ТЗ 6.2, модель `DeviceProfile`).
class DeviceProfile {
  const DeviceProfile({
    required this.id,
    required this.name,
    required this.broadcastPrefixHex,
    required this.manufacturerId,
    required this.channels,
    this.barcode,
    this.localImagePath,
    this.createdAt,
  });

  final String id;
  final String? barcode;
  final String name;
  final String? localImagePath;

  /// 8-байтовый префикс устройства, HEX (ТЗ 5.1).
  final String broadcastPrefixHex;

  /// Manufacturer ID для Android ManufacturerData (0xFFF0 = 65520).
  final int manufacturerId;
  final List<DeviceChannel> channels;
  final DateTime? createdAt;

  factory DeviceProfile.fromJson(Map<String, dynamic> json) => DeviceProfile(
        id: json['id'] as String,
        barcode: json['barcode'] as String?,
        name: json['name'] as String,
        localImagePath: json['localImagePath'] as String?,
        broadcastPrefixHex: json['broadcastPrefixHex'] as String,
        manufacturerId: (json['manufacturerId'] as num?)?.toInt() ?? 65520,
        channels: ((json['channels'] as List<dynamic>?) ?? <dynamic>[])
            .map((e) => DeviceChannel.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        if (barcode != null) 'barcode': barcode,
        'name': name,
        if (localImagePath != null) 'localImagePath': localImagePath,
        'broadcastPrefixHex': broadcastPrefixHex,
        'manufacturerId': manufacturerId,
        'channels': channels.map((c) => c.toJson()).toList(),
        if (createdAt != null)
          'createdAt': createdAt!.toUtc().toIso8601String(),
      };

  /// Первый канал (для одноканальных устройств).
  DeviceChannel? get primaryChannel =>
      channels.isEmpty ? null : channels.first;
}

/// Событие записанного ритма: `(atMs, channelId, cmdHex)` (ТЗ 6.2).
class PatternEvent {
  const PatternEvent({
    required this.atMs,
    required this.channelId,
    required this.cmdHex,
  });

  final int atMs;
  final String channelId;
  final String cmdHex;

  factory PatternEvent.fromJson(Map<String, dynamic> json) => PatternEvent(
        atMs: (json['atMs'] as num).toInt(),
        channelId: json['channelId'] as String,
        cmdHex: json['cmdHex'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'atMs': atMs,
        'channelId': channelId,
        'cmdHex': cmdHex,
      };
}

/// Записанный паттерн — «Ритм» (ТЗ 6.2, модель `RecordedPattern`).
class RecordedPattern {
  const RecordedPattern({
    required this.id,
    required this.name,
    required this.deviceId,
    required this.durationMs,
    required this.events,
  });

  final String id;
  final String name;
  final String deviceId;
  final int durationMs;
  final List<PatternEvent> events;

  factory RecordedPattern.fromJson(Map<String, dynamic> json) =>
      RecordedPattern(
        id: json['id'] as String,
        name: json['name'] as String,
        deviceId: json['deviceId'] as String,
        durationMs: (json['durationMs'] as num).toInt(),
        events: ((json['events'] as List<dynamic>?) ?? <dynamic>[])
            .map((e) => PatternEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'deviceId': deviceId,
        'durationMs': durationMs,
        'events': events.map((e) => e.toJson()).toList(),
      };
}

/// Полный экспорт/импорт локальной базы (ТЗ 3.2.5 «Данные»).
class AppBackup {
  const AppBackup({
    required this.version,
    required this.devices,
    required this.patterns,
  });

  final int version;
  final List<DeviceProfile> devices;
  final List<RecordedPattern> patterns;

  static const int schemaVersion = 1;

  factory AppBackup.fromJson(Map<String, dynamic> json) => AppBackup(
        version: (json['version'] as num?)?.toInt() ?? schemaVersion,
        devices: ((json['devices'] as List<dynamic>?) ?? <dynamic>[])
            .map((e) => DeviceProfile.fromJson(e as Map<String, dynamic>))
            .toList(),
        patterns: ((json['patterns'] as List<dynamic>?) ?? <dynamic>[])
            .map((e) => RecordedPattern.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'devices': devices.map((d) => d.toJson()).toList(),
        'patterns': patterns.map((p) => p.toJson()).toList(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static AppBackup decode(String source) =>
      AppBackup.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
