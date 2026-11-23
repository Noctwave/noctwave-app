import 'dart:async';

import 'ble_advertiser.dart';
import 'tx_log.dart';

/// Обёртка над [BleAdvertiserGateway], журналирующая каждую отправку
/// в [TxLog] (ТЗ 4.6.3 — инспектор пакетов). Журнал живёт только в RAM.
class LoggingBleGateway implements BleAdvertiserGateway {
  LoggingBleGateway(this._inner, this._log);

  final BleAdvertiserGateway _inner;
  final TxLog _log;

  @override
  Future<void> broadcastCommand({
    required String prefixHex,
    required String commandHex,
    required int manufacturerId,
    required int durationMs,
  }) async {
    _log.add(TxLogEntry(
      timestamp: DateTime.now(),
      prefixHex: prefixHex,
      commandHex: commandHex,
      isStop: false,
      durationMs: durationMs,
      manufacturerId: manufacturerId,
    ));
    await _inner.broadcastCommand(
      prefixHex: prefixHex,
      commandHex: commandHex,
      manufacturerId: manufacturerId,
      durationMs: durationMs,
    );
  }

  @override
  Future<void> broadcastStop({
    required String prefixHex,
    required String stopHex,
    required int manufacturerId,
    required int durationMs,
  }) async {
    _log.add(TxLogEntry(
      timestamp: DateTime.now(),
      prefixHex: prefixHex,
      commandHex: stopHex,
      isStop: true,
      durationMs: durationMs,
      manufacturerId: manufacturerId,
    ));
    await _inner.broadcastStop(
      prefixHex: prefixHex,
      stopHex: stopHex,
      manufacturerId: manufacturerId,
      durationMs: durationMs,
    );
  }

  @override
  Future<BluetoothAdapterState> getBluetoothState() =>
      _inner.getBluetoothState();

  @override
  Future<Map<String, Object>> previewEncodedPacket({
    required String prefixHex,
    required String commandHex,
  }) =>
      _inner.previewEncodedPacket(
          prefixHex: prefixHex, commandHex: commandHex);

  @override
  Future<void> stopAdvertising() => _inner.stopAdvertising();
}
