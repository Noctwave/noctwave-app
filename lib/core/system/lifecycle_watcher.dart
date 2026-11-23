import 'package:flutter/widgets.dart';

/// Наблюдатель жизненного цикла приложения (AppLifecycleListener).
///
/// На iOS сворачивание или блокировка экрана останавливает передачу
/// ServiceUUIDs: iOS переносит их в overflow area, и пакет становится
/// нечитаемым для устройства (ТЗ 5.3, 3.2.4). Этот детектор даёт UI
/// вовремя предупредить пользователя или включить OLED-замок.
class LifecycleWatcher {
  LifecycleWatcher({this.onBackground, this.onForeground});

  /// Приложение ушло в фон/экран заблокирован.
  final void Function()? onBackground;

  /// Приложение вернулось на передний план.
  final void Function()? onForeground;

  AppLifecycleListener? _listener;

  void start() {
    _listener = AppLifecycleListener(
      onStateChange: (state) {
        switch (state) {
          case AppLifecycleState.hidden:
          case AppLifecycleState.paused:
          case AppLifecycleState.inactive:
            onBackground?.call();
          case AppLifecycleState.resumed:
            onForeground?.call();
          case AppLifecycleState.detached:
            break;
        }
      },
    );
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}
