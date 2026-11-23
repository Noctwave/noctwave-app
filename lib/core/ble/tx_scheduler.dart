import 'dart:async';

import 'ble_advertiser.dart';

/// Параметры BLE-движка (ТЗ 5.4 и 4.6.4 — тюнинг Debug Mode).
class TxSchedulerConfig {
  const TxSchedulerConfig({
    this.burstDurationMs = 350,
    this.stopBurstDurationMs = 700,
    this.minTxIntervalMs = 180,
  });

  /// Длительность одиночного burst-окна, мс (по умолчанию 350, ТЗ 5.4.3).
  final int burstDurationMs;

  /// Длительность приоритетного burst-окна СТОП, мс (по умолчанию 700, ТЗ 5.4.4).
  final int stopBurstDurationMs;

  /// Минимальный интервал перезапуска рекламы, мс (ТЗ 5.4.2: 160–200).
  final int minTxIntervalMs;

  TxSchedulerConfig copyWith({
    int? burstDurationMs,
    int? stopBurstDurationMs,
    int? minTxIntervalMs,
  }) =>
      TxSchedulerConfig(
        burstDurationMs: burstDurationMs ?? this.burstDurationMs,
        stopBurstDurationMs: stopBurstDurationMs ?? this.stopBurstDurationMs,
        minTxIntervalMs: minTxIntervalMs ?? this.minTxIntervalMs,
      );
}

/// Планировщик передачи (ТЗ 5.4): квантование, троттлинг 4–6 Гц,
/// дедупликация, burst-окна и приоритетная команда СТОП.
///
/// Для детерминированных тестов время инжектится через [TxScheduler.new]
/// (`currentTimeMs`).
class TxScheduler {
  TxScheduler({
    required this._gateway,
    this._config = const TxSchedulerConfig(),
    int Function()? currentTimeMs,
  }) : _now = currentTimeMs ?? _systemNow;

  final BleAdvertiserGateway _gateway;
  final TxSchedulerConfig _config;
  final int Function() _now;

  static int _systemNow() => DateTime.now().millisecondsSinceEpoch;

  Timer? _burstTimer;
  Future<void> _sendChain = Future<void>.value();
  int _sendEpoch = 0;

  String _lastCommandHex = '';
  int _lastTxAtMs = -1;

  /// Идёт ли активное burst-окно.
  bool get isBurstActive => _burstTimer?.isActive ?? false;

  /// Квантует непрерывный сигнал `u ∈ [0, 1]` в HEX ступени (ТЗ 5.4.1):
  /// `i = round(u · (N − 1))`; при `u = 0` всегда стоп-команда.
  static String quantize({
    required double u,
    required List<String> intensityStepsHex,
    required String stopCmdHex,
  }) {
    if (intensityStepsHex.isEmpty) {
      throw ArgumentError('intensityStepsHex не может быть пустым');
    }
    final clamped = u.clamp(0.0, 1.0);
    if (clamped <= 0) {
      return stopCmdHex;
    }
    final index = (clamped * (intensityStepsHex.length - 1)).round();
    return intensityStepsHex[index];
  }

  /// Одиночная команда кнопки «Пульта» (ТЗ 5.4.3): перезапускает рекламу
  /// на `burstDurationMs`, затем автоостановка ради экономии батареи.
  Future<void> sendBurstCommand({
    required String prefixHex,
    required String commandHex,
    required int manufacturerId,
  }) async {
    _burstTimer?.cancel();
    _burstTimer = null;
    _sendEpoch++;
    await _sendChain;
    _sendChain = _sendChain.then((_) => _send(
          prefixHex: prefixHex,
          commandHex: commandHex,
          manufacturerId: manufacturerId,
          durationMs: _config.burstDurationMs,
        ));
    await _sendChain;
    _lastCommandHex = commandHex;
    _armBurstEnd(_config.burstDurationMs);
  }

  /// Обновление команды в динамическом режиме (ТЗ 5.4.2): пакет
  /// перезапускается только при изменении HEX-кода и не чаще
  /// `minTxIntervalMs` (троттлинг 4–6 Гц против
  /// `ADVERTISE_FAILED_TOO_MANY_ADVERTISERS`).
  Future<void> updateDynamicCommand({
    required String prefixHex,
    required String commandHex,
    required int manufacturerId,
  }) async {
    if (commandHex == _lastCommandHex) {
      return; // дедупликация: HEX не изменился
    }
    final epoch = _sendEpoch;
    final now = _now();
    final sinceLastTx =
        _lastTxAtMs < 0 ? _config.minTxIntervalMs : now - _lastTxAtMs;
    final delayMs = sinceLastTx < _config.minTxIntervalMs
        ? _config.minTxIntervalMs - sinceLastTx
        : 0;

    _burstTimer?.cancel();
    _burstTimer = null;
    _sendChain = _sendChain.then((_) async {
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      if (epoch != _sendEpoch) {
        return; // устаревшая команда: СТОП или новая отменили её
      }
      await _send(
        prefixHex: prefixHex,
        commandHex: commandHex,
        manufacturerId: manufacturerId,
        durationMs: 0,
      );
    });
    _lastCommandHex = commandHex;
    await _sendChain;
  }

  /// Приоритетный СТОП (ТЗ 5.4.4): отменяет активный burst и отложенные
  /// отправки, вещает `stopCmdHex` на `stopBurstDurationMs`.
  Future<void> stop({
    required String prefixHex,
    required String stopCmdHex,
    required int manufacturerId,
  }) async {
    _burstTimer?.cancel();
    _burstTimer = null;
    _sendEpoch++; // все отложенные динамические отправки аннулируются
    final epoch = _sendEpoch;
    _sendChain = _sendChain.then((_) async {
      if (epoch != _sendEpoch) return;
      await _gateway.broadcastStop(
        prefixHex: prefixHex,
        stopHex: stopCmdHex,
        manufacturerId: manufacturerId,
        durationMs: _config.stopBurstDurationMs,
      );
      _lastTxAtMs = _now();
    });
    _lastCommandHex = stopCmdHex;
    await _sendChain;
    _armBurstEnd(_config.stopBurstDurationMs);
  }

  /// Полная остановка движка (выход с экрана управления, dispose).
  Future<void> dispose() async {
    _burstTimer?.cancel();
    _burstTimer = null;
    _sendEpoch++;
    _lastCommandHex = '';
    _lastTxAtMs = -1;
    await _sendChain;
    await _gateway.stopAdvertising();
  }

  Future<void> _send({
    required String prefixHex,
    required String commandHex,
    required int manufacturerId,
    required int durationMs,
  }) async {
    await _gateway.broadcastCommand(
      prefixHex: prefixHex,
      commandHex: commandHex,
      manufacturerId: manufacturerId,
      durationMs: durationMs,
    );
    _lastTxAtMs = _now();
  }

  void _armBurstEnd(int durationMs) {
    _burstTimer?.cancel();
    _burstTimer = Timer(Duration(milliseconds: durationMs), () {
      _burstTimer = null;
      unawaited(_gateway.stopAdvertising());
    });
  }
}
