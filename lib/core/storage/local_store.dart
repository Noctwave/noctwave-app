import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_profile.dart';

/// Локальное хранилище приложения (ТЗ 6.2): профили устройств, записанные
/// ритмы и настройки. Offline-first: всё живёт на устройстве, полная
/// сериализация в JSON для экспорта/импорта (ТЗ 3.2.5 «Данные»).
///
/// MVP-реализация поверх SharedPreferences (JSON-документы). На Этапе 2
/// при росте объёма ритмов переезжает на Drift/SQLite без смены API.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static const _devicesKey = 'noctwave.devices.v1';
  static const _patternsKey = 'noctwave.patterns.v1';
  static const _settingsKey = 'noctwave.settings.v1';

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  // ── Устройства ──────────────────────────────────────────────────────

  List<DeviceProfile> loadDevices() {
    final raw = _prefs.getString(_devicesKey);
    if (raw == null || raw.isEmpty) return <DeviceProfile>[];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => DeviceProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveDevices(List<DeviceProfile> devices) =>
      _prefs.setString(
        _devicesKey,
        jsonEncode(devices.map((d) => d.toJson()).toList()),
      );

  // ── Ритмы ───────────────────────────────────────────────────────────

  List<RecordedPattern> loadPatterns() {
    final raw = _prefs.getString(_patternsKey);
    if (raw == null || raw.isEmpty) return <RecordedPattern>[];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => RecordedPattern.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePatterns(List<RecordedPattern> patterns) =>
      _prefs.setString(
        _patternsKey,
        jsonEncode(patterns.map((p) => p.toJson()).toList()),
      );

  // ── Настройки ───────────────────────────────────────────────────────

  AppSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings settings) =>
      _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));

  // ── Экспорт / импорт всей базы (ТЗ 3.2.5) ──────────────────────────

  AppBackup exportBackup() => AppBackup(
        version: AppBackup.schemaVersion,
        devices: loadDevices(),
        patterns: loadPatterns(),
      );

  Future<void> importBackup(AppBackup backup) async {
    await saveDevices(backup.devices);
    await savePatterns(backup.patterns);
  }
}

/// Локальные настройки (ТЗ 3.2.5 «Профиль»).
class AppSettings {
  const AppSettings({
    this.hapticsEnabled = true,
    this.pulseAnimation = true,
    this.volumeDownStop = true,
    this.kegelModule = false,
    this.videoModule = false,
    this.debugModeEnabled = false,
    this.autoStopOnExit = true,
    this.accentColorValue = 0xFF6366F1,
    this.burstDurationMs = 350,
    this.stopBurstDurationMs = 700,
    this.minTxIntervalMs = 180,
    this.appPinHash,
    this.biometricUnlock = false,
    this.themeMode = 'system',
  });

  /// Тактильный отклик (ТЗ 3.1).
  final bool hapticsEnabled;

  /// Пульсация интерфейса в такт интенсивности.
  final bool pulseAnimation;

  /// Громкость вниз = Экстренный СТОП (в т.ч. на OLED-замке).
  final bool volumeDownStop;

  /// Видимость опциональных модулей.
  final bool kegelModule;
  final bool videoModule;

  /// Debug Mode (скрытый вход: 5 тапов по версии).
  final bool debugModeEnabled;

  /// Авто-СТОП при выходе с экрана управления.
  final bool autoStopOnExit;

  /// Акцентный цвет ARGB (по умолчанию индиго #6366F1).
  final int accentColorValue;

  /// Тюнинг BLE-движка (ТЗ 4.6.4 / 5.4).
  final int burstDurationMs;
  final int stopBurstDurationMs;
  final int minTxIntervalMs;

  /// Хэш PIN-кода блокировки приложения (null = PIN не задан).
  final String? appPinHash;

  /// Разблокировка по FaceID/TouchID (ТЗ 3.2.5 «Приватность»).
  final bool biometricUnlock;

  /// Тема: 'system' (под тему ОС), 'dark', 'light'.
  final String themeMode;

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        hapticsEnabled: (json['hapticsEnabled'] as bool?) ?? true,
        pulseAnimation: (json['pulseAnimation'] as bool?) ?? true,
        volumeDownStop: (json['volumeDownStop'] as bool?) ?? true,
        kegelModule: (json['kegelModule'] as bool?) ?? false,
        videoModule: (json['videoModule'] as bool?) ?? false,
        debugModeEnabled: (json['debugModeEnabled'] as bool?) ?? false,
        autoStopOnExit: (json['autoStopOnExit'] as bool?) ?? true,
        accentColorValue:
            (json['accentColorValue'] as num?)?.toInt() ?? 0xFF6366F1,
        burstDurationMs: (json['burstDurationMs'] as num?)?.toInt() ?? 350,
        stopBurstDurationMs:
            (json['stopBurstDurationMs'] as num?)?.toInt() ?? 700,
        minTxIntervalMs: (json['minTxIntervalMs'] as num?)?.toInt() ?? 180,
        appPinHash: json['appPinHash'] as String?,
        biometricUnlock: (json['biometricUnlock'] as bool?) ?? false,
        themeMode: (json['themeMode'] as String?) ?? 'system',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hapticsEnabled': hapticsEnabled,
        'pulseAnimation': pulseAnimation,
        'volumeDownStop': volumeDownStop,
        'kegelModule': kegelModule,
        'videoModule': videoModule,
        'debugModeEnabled': debugModeEnabled,
        'autoStopOnExit': autoStopOnExit,
        'accentColorValue': accentColorValue,
        'burstDurationMs': burstDurationMs,
        'stopBurstDurationMs': stopBurstDurationMs,
        'minTxIntervalMs': minTxIntervalMs,
        if (appPinHash != null) 'appPinHash': appPinHash,
        'biometricUnlock': biometricUnlock,
        'themeMode': themeMode,
      };

  AppSettings copyWith({
    bool? hapticsEnabled,
    bool? pulseAnimation,
    bool? volumeDownStop,
    bool? kegelModule,
    bool? videoModule,
    bool? debugModeEnabled,
    bool? autoStopOnExit,
    int? accentColorValue,
    int? burstDurationMs,
    int? stopBurstDurationMs,
    int? minTxIntervalMs,
    String? appPinHash,
    bool clearPinHash = false,
    bool? biometricUnlock,
    String? themeMode,
  }) =>
      AppSettings(
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        pulseAnimation: pulseAnimation ?? this.pulseAnimation,
        volumeDownStop: volumeDownStop ?? this.volumeDownStop,
        kegelModule: kegelModule ?? this.kegelModule,
        videoModule: videoModule ?? this.videoModule,
        debugModeEnabled: debugModeEnabled ?? this.debugModeEnabled,
        autoStopOnExit: autoStopOnExit ?? this.autoStopOnExit,
        accentColorValue: accentColorValue ?? this.accentColorValue,
        burstDurationMs: burstDurationMs ?? this.burstDurationMs,
        stopBurstDurationMs: stopBurstDurationMs ?? this.stopBurstDurationMs,
        minTxIntervalMs: minTxIntervalMs ?? this.minTxIntervalMs,
        appPinHash: clearPinHash ? null : (appPinHash ?? this.appPinHash),
        biometricUnlock: biometricUnlock ?? this.biometricUnlock,
        themeMode: themeMode ?? this.themeMode,
      );
}
