import 'dart:typed_data';

/// Кодирование команд протокола LoveSpouse (ТЗ, раздел 5).
///
/// Логический пейлоад — 11 байт: 8-байтовый префикс устройства + 3-байтовая
/// команда. Android передаёт его как ManufacturerData (0xFFF0), iOS —
/// как шесть 16-битных Service UUID с XOR pre-whitening (ТЗ 5.3).
class LoveSpouseCodec {
  LoveSpouseCodec._();

  /// 11-байтовая константная маска XOR pre-whitening (ТЗ 5.3).
  static const List<int> xorMask = <int>[
    0x94, 0xBE, 0x0A, 0xED, 0x39, 0x35, 0x83, 0xAD, 0x8B, 0x89, 0x40,
  ];

  /// Байт-завершитель, дописываемый после XOR (ТЗ 5.3, шаг 2).
  static const int terminator = 0x0B;

  /// Длина префикса устройства в байтах.
  static const int prefixLength = 8;

  /// Длина кода команды в байтах.
  static const int commandLength = 3;

  /// Полная длина пейлоада.
  static const int payloadLength = prefixLength + commandLength;

  /// Парсит HEX-строку произвольного регистра в байты.
  static Uint8List parseHex(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.length.isOdd) {
      throw FormatException('HEX-строка должна содержать чётное число цифр', hex);
    }
    final bytes = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Форматирует байты в верхнерегистровый HEX без разделителей.
  static String toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();

  /// Собирает сырой 11-байтовый пейлоад `prefix[0..7] + command[0..2]`.
  static Uint8List rawPayload(String prefixHex, String commandHex) {
    final prefix = parseHex(prefixHex);
    final command = parseHex(commandHex);
    if (prefix.length != prefixLength) {
      throw FormatException(
        'Префикс должен быть $prefixLength байт, получено ${prefix.length}',
        prefixHex,
      );
    }
    if (command.length != commandLength) {
      throw FormatException(
        'Команда должна быть $commandLength байт, получено ${command.length}',
        commandHex,
      );
    }
    return Uint8List.fromList(<int>[...prefix, ...command]);
  }

  /// XOR pre-whitening: `E_k = raw_k XOR M_k`, затем байт-завершитель 0x0B.
  /// Возвращает 12 байт (ТЗ 5.3, шаги 1–2).
  static Uint8List encodeWhitened(Uint8List raw) {
    if (raw.length != payloadLength) {
      throw ArgumentError('Ожидался пейлоад из $payloadLength байт');
    }
    final encoded = Uint8List(payloadLength + 1);
    for (var k = 0; k < payloadLength; k++) {
      encoded[k] = raw[k] ^ xorMask[k];
    }
    encoded[payloadLength] = terminator;
    return encoded;
  }

  /// Упаковывает 12 whitened-байт в шесть 16-битных CBUUID (ТЗ 5.3, шаги 3–4).
  ///
  /// Пара (E_2j, E_2j+1) меняется местами (Little-Endian):
  /// uuid_j = HEX(E_2j+1) + HEX(E_2j).
  /// Порядок UUID в списке строго сохраняется — Array, не Set.
  static List<String> encodeIosUuids(String prefixHex, String commandHex) {
    final encoded = encodeWhitened(rawPayload(prefixHex, commandHex));
    final uuids = <String>[];
    for (var j = 0; j < 6; j++) {
      final lo = encoded[j * 2];
      final hi = encoded[j * 2 + 1];
      final hex = '${hi.toRadixString(16).padLeft(2, '0')}'
          '${lo.toRadixString(16).padLeft(2, '0')}';
      uuids.add(hex.toUpperCase());
    }
    return uuids;
  }

  /// Отладочное представление пакета для Debug Mode (ТЗ 7.2).
  static Map<String, Object> preview(String prefixHex, String commandHex) {
    final raw = rawPayload(prefixHex, commandHex);
    final whitened = encodeWhitened(raw);
    return <String, Object>{
      'rawHex': toHex(raw),
      'whitenedHex': toHex(whitened),
      'iosServiceUuids': encodeIosUuids(prefixHex, commandHex),
    };
  }
}
