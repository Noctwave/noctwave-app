import 'dart:collection';

import '../ble/love_spouse_codec.dart';

/// Запись отправленного BLE-пакета для инспектора Debug Mode (ТЗ 4.6.3).
class TxLogEntry {
  TxLogEntry({
    required this.timestamp,
    required this.prefixHex,
    required this.commandHex,
    required this.isStop,
    required this.durationMs,
    this.manufacturerId = 0xFFF0,
  });

  final DateTime timestamp;
  final String prefixHex;
  final String commandHex;
  final bool isStop;
  final int durationMs;
  final int manufacturerId;

  /// Сырой 11-байтовый пейлоад.
  String get rawHex =>
      LoveSpouseCodec.toHex(LoveSpouseCodec.rawPayload(prefixHex, commandHex));

  /// Android ManufacturerData (тот же 11-байтовый пейлоад).
  String get manufacturerDataHex => rawHex;

  /// Шесть 16-битных CBUUID после XOR pre-whitening (iOS).
  List<String> get iosServiceUuids =>
      LoveSpouseCodec.encodeIosUuids(prefixHex, commandHex);
}

/// In-memory ring-buffer последних отправленных пакетов (ТЗ 8.5):
/// максимум 200 записей, ничего не пишется на диск, очищается при
/// закрытии приложения. Единственный журнал Debug Mode.
class TxLog {
  TxLog({this.capacity = 200});

  final int capacity;
  final Queue<TxLogEntry> _entries = Queue<TxLogEntry>();

  /// Слушатели изменений (инспектор пакетов обновляется live).
  final List<void Function()> _listeners = <void Function()>[];

  List<TxLogEntry> get entries => List<TxLogEntry>.unmodifiable(
        _entries.toList().reversed,
      );

  int get length => _entries.length;

  void add(TxLogEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void clear() {
    _entries.clear();
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }
}
