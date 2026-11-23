import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

/// Мост к sensors_plus (ТЗ 4.4): создаётся лениво, только при входе
/// в режим «Сенсоры». В тестах и на desktop возвращает null —
/// режим показывает заглушку, остальные режимы не затронуты.
class _SensorsBridge {
  _SensorsBridge._();

  static _SensorsBridge? _instance;

  /// Stream событий акселерометра (x, y, z) в м/с².
  Stream<(double, double, double)> get accelerometerEvents =>
      accelerometerEventStream().map((e) => (e.x, e.y, e.z));

  static _SensorsBridge? get instance => _instance;

  static Future<_SensorsBridge?> init() async {
    if (_instance != null) return _instance;
    try {
      // Проверяем, что сенсор вообще доступен, первым чтением.
      await accelerometerEventStream().first.timeout(
        const Duration(seconds: 1),
      );
      _instance = _SensorsBridge._();
      return _instance;
    } catch (_) {
      return null;
    }
  }
}

typedef SensorsBridge = _SensorsBridge;

/// Публичный доступ для ControlPage.
SensorsBridge? get sensorBridge => _SensorsBridge.instance;

/// Инициализация ("вызывается при входе в режим").
Future<SensorsBridge?> initSensors() => _SensorsBridge.init();
