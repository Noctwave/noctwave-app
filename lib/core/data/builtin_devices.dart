import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/device_profile.dart';

/// Встроенная оффлайн-база пресетов (ТЗ 6.2, assets/builtin_devices.json):
/// семейства префиксов, типовые наборы команд для 1/2-моторных, вакуумных
/// и нагревательных устройств, банки команд для Command Hunter.
class BuiltinDevices {
  BuiltinDevices._(this.profiles, this.commandBanks);

  final List<DeviceProfile> profiles;

  /// Банки 3-байтовых команд для пошагового перебора в Debug Mode.
  final List<CommandBank> commandBanks;

  static Future<BuiltinDevices> load() async {
    final raw = await rootBundle.loadString('assets/builtin_devices.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final profiles = (json['devices'] as List<dynamic>)
        .map((e) => DeviceProfile.fromJson(e as Map<String, dynamic>))
        .toList();
    final banks = ((json['commandBanks'] as List<dynamic>?) ?? <dynamic>[])
        .map((e) => CommandBank.fromJson(e as Map<String, dynamic>))
        .toList();
    return BuiltinDevices._(profiles, banks);
  }

  /// Клонирует встроенный профиль как пользовательский (новый id, дата).
  static DeviceProfile instantiate(DeviceProfile template) {
    final json = template.toJson();
    json['id'] =
        'builtin-${template.id}-${DateTime.now().millisecondsSinceEpoch}';
    json['createdAt'] = DateTime.now().toUtc().toIso8601String();
    json.remove('barcode');
    return DeviceProfile.fromJson(json);
  }
}

/// Банк команд для «Сыщика команд» (ТЗ 4.6.1).
class CommandBank {
  const CommandBank({required this.name, required this.commands});

  final String name;
  final List<String> commands;

  factory CommandBank.fromJson(Map<String, dynamic> json) => CommandBank(
        name: json['name'] as String,
        commands: (json['commands'] as List<dynamic>).cast<String>(),
      );
}
