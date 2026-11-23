import 'dart:async';

import 'package:flutter/services.dart';

/// Нативные системные функции OLED-замка (ТЗ 3.2.4):
/// - wakelock: экран не гаснет, пока активен замок
///   (Android: FLAG_KEEP_SCREEN_ON; iOS: isIdleTimerDisabled);
/// - аппаратная «Громкость вниз» → приоритетный СТОП
///   (Android: KeyEvent KEYCODE_VOLUME_DOWN; событие шлётся в Dart).
class SystemControls {
  SystemControls({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.pulselocal/system_controls') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;

  /// Колбэк нажатия «Громкость вниз» (экстренный СТОП).
  void Function()? onVolumeDown;

  Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', enabled);
    } on PlatformException {
      // Функция некритична: без wakelock замок продолжает работать.
    } on MissingPluginException {
      // Платформа без нативного модуля (тесты, desktop).
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'volumeDown') {
      onVolumeDown?.call();
    }
    return null;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    onVolumeDown = null;
  }
}
