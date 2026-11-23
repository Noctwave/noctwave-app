import 'dart:async';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Статус BLE-адаптера платформы (ТЗ 7.2, `getBluetoothState`).
enum BluetoothAdapterState { unknown, ready, poweredOff, unauthorized, unsupported }

/// Контракт нативного BLE-моста `com.pulselocal/ble_advertiser` (ТЗ 7.2).
///
/// Единый интерфейс над:
/// - Android: `BluetoothLeAdvertiser` + ManufacturerData 0xFFF0 (ТЗ 5.2);
/// - iOS: `CBPeripheralManager` + шесть Service CBUUID (ТЗ 5.3).
abstract class BleAdvertiserGateway {
  Future<BluetoothAdapterState> getBluetoothState();

  /// Вещает `commandHex` для устройства с префиксом `prefixHex` в течение
  /// `durationMs` (0 = до следующей команды).
  Future<void> broadcastCommand({
    required String prefixHex,
    required String commandHex,
    required int manufacturerId,
    required int durationMs,
  });

  /// Прерывает текущую передачу и с высшим приоритетом вещает стоп-пакет.
  Future<void> broadcastStop({
    required String prefixHex,
    required String stopHex,
    required int manufacturerId,
    required int durationMs,
  });

  /// Немедленно выключает BLE-рекламу.
  Future<void> stopAdvertising();

  /// Отладочное представление пакета (сырой HEX или 6 CBUUID).
  Future<Map<String, Object>> previewEncodedPacket({
    required String prefixHex,
    required String commandHex,
  });
}

/// Реализация моста через `MethodChannel` к нативному Kotlin/Swift-слою.
class MethodChannelBleAdvertiser implements BleAdvertiserGateway {
  MethodChannelBleAdvertiser({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.pulselocal/ble_advertiser');

  final MethodChannel _channel;

  @override
  Future<BluetoothAdapterState> getBluetoothState() async {
    final raw = await _channel.invokeMethod<String>('getBluetoothState');
    return switch (raw) {
      'ready' => BluetoothAdapterState.ready,
      'poweredOff' => BluetoothAdapterState.poweredOff,
      'unauthorized' => BluetoothAdapterState.unauthorized,
      'unsupported' => BluetoothAdapterState.unsupported,
      _ => BluetoothAdapterState.unknown,
    };
  }

  @override
  Future<void> broadcastCommand({
    required String prefixHex,
    required String commandHex,
    required int manufacturerId,
    required int durationMs,
  }) =>
      _channel.invokeMethod<void>(
        'broadcastCommand',
        <String, Object>{
          'prefixHex': prefixHex,
          'commandHex': commandHex,
          'manufacturerId': manufacturerId,
          'durationMs': durationMs,
        },
      );

  @override
  Future<void> broadcastStop({
    required String prefixHex,
    required String stopHex,
    required int manufacturerId,
    required int durationMs,
  }) =>
      _channel.invokeMethod<void>(
        'broadcastStop',
        <String, Object>{
          'prefixHex': prefixHex,
          'stopHex': stopHex,
          'manufacturerId': manufacturerId,
          'durationMs': durationMs,
        },
      );

  @override
  Future<void> stopAdvertising() => _channel.invokeMethod<void>('stopAdvertising');

  @override
  Future<Map<String, Object>> previewEncodedPacket({
    required String prefixHex,
    required String commandHex,
  }) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'previewEncodedPacket',
      <String, Object>{'prefixHex': prefixHex, 'commandHex': commandHex},
    );
    if (result == null) {
      throw PlatformException(
        code: 'NULL_PREVIEW',
        message: 'Нативный слой вернул пустой preview',
      );
    }
    return result.cast<String, Object>();
  }
}

/// In-memory транспорт для тестов и отладки: не трогает радиочасть,
/// журналирует все вызовы.
class InMemoryBleAdvertiser implements BleAdvertiserGateway {
  final List<Map<String, Object?>> calls = <Map<String, Object?>>[];

  BluetoothAdapterState state = BluetoothAdapterState.ready;

  /// Значение, возвращаемое [previewEncodedPacket].
  Map<String, Object> previewResult = const <String, Object>{};

  @override
  Future<BluetoothAdapterState> getBluetoothState() async {
    calls.add(<String, Object?>{'method': 'getBluetoothState'});
    return state;
  }

  @override
  Future<void> broadcastCommand({
    required String prefixHex,
    required String commandHex,
    required int manufacturerId,
    required int durationMs,
  }) async {
    calls.add(<String, Object?>{
      'method': 'broadcastCommand',
      'prefixHex': prefixHex,
      'commandHex': commandHex,
      'manufacturerId': manufacturerId,
      'durationMs': durationMs,
    });
  }

  @override
  Future<void> broadcastStop({
    required String prefixHex,
    required String stopHex,
    required int manufacturerId,
    required int durationMs,
  }) async {
    calls.add(<String, Object?>{
      'method': 'broadcastStop',
      'prefixHex': prefixHex,
      'stopHex': stopHex,
      'manufacturerId': manufacturerId,
      'durationMs': durationMs,
    });
  }

  @override
  Future<void> stopAdvertising() async {
    calls.add(<String, Object?>{'method': 'stopAdvertising'});
  }

  @override
  Future<Map<String, Object>> previewEncodedPacket({
    required String prefixHex,
    required String commandHex,
  }) async =>
      previewResult;

  /// Очищает журнал (тесты, Debug-режим).
  @visibleForTesting
  void clear() => calls.clear();
}
