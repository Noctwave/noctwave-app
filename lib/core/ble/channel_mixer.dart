import 'dart:async';

import 'ble_advertiser.dart';

/// Непрерывная поканальная передача (ТЗ 5.4, watchdog ~800 мс).
///
/// Устройство помнит последнюю команду КАЖДОГО канала и работает, пока
/// получает broadcast. iOS может вещать только один пакет за раз, поэтому
/// активные каналы чередуются (round-robin) с интервалом ~250 мс — каждый
/// канал обновляется чаще watchdog, и переключение/включение одного мотора
/// НЕ сбрасывает другой.
class ChannelMixer {
  ChannelMixer({
    required this._gateway,
    required this._prefixHex,
    required this._manufacturerId,
    this.tickMs = 250,
  });
  final BleAdvertiserGateway _gateway;
  final String _prefixHex;
  final int _manufacturerId;
  final int tickMs;

  /// channelId → текущая команда (null/стоп = канал не вещаем).
  final Map<String, String> _active = <String, String>{};
  final Map<String, String> _stopCmd = <String, String>{};

  Timer? _timer;
  int _cursor = 0;
  bool _sending = false;

  bool get isRunning => _timer?.isActive ?? false;

  /// Регистрирует стоп-команду канала (для корректного СТОП).
  void registerStop(String channelId, String stopHex) {
    _stopCmd[channelId] = stopHex;
  }

  /// Устанавливает команду канала и запускает непрерывное вещание.
  void setCommand(String channelId, String cmdHex) {
    _active[channelId] = cmdHex;
    _ensureRunning();
  }

  /// Останавливает канал: шлёт его стоп и убирает из ротации.
  void stopChannel(String channelId) {
    final stop = _stopCmd[channelId];
    _active.remove(channelId);
    if (stop != null) {
      unawaited(_gateway.broadcastStop(
        prefixHex: _prefixHex,
        stopHex: stop,
        manufacturerId: _manufacturerId,
        durationMs: 700,
      ));
    }
    if (_active.isEmpty) _stopTimer();
  }

  /// Полный СТОП: все каналы стоп, ротация остановлена.
  Future<void> stopAll() async {
    _stopTimer();
    final stops = _stopCmd.values.toSet();
    _active.clear();
    for (final stop in stops) {
      await _gateway.broadcastStop(
        prefixHex: _prefixHex,
        stopHex: stop,
        manufacturerId: _manufacturerId,
        durationMs: 700,
      );
    }
  }

  void _ensureRunning() {
    if (_timer != null) return;
    _timer = Timer.periodic(Duration(milliseconds: tickMs), (_) => _tick());
    _tick();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _cursor = 0;
  }

  Future<void> _tick() async {
    if (_sending || _active.isEmpty) return;
    _sending = true;
    try {
      final ids = _active.keys.toList();
      _cursor %= ids.length;
      final id = ids[_cursor];
      _cursor++;
      final cmd = _active[id];
      if (cmd != null) {
        await _gateway.broadcastCommand(
          prefixHex: _prefixHex,
          commandHex: cmd,
          manufacturerId: _manufacturerId,
          durationMs: 0,
        );
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> dispose() async {
    _stopTimer();
    _active.clear();
  }
}
