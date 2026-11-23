import 'dart:typed_data';

/// Кодировщик радио-пакетов BroadLink Fastcon BLE (протокол LoveSpouse).
///
/// Порт RfPayloadEncoder из hirusha-adi/love-spouse-controller (MIT).
/// Сырой префикс из API zlmicro (5 байт, напр. "77 62 4d 53 45" = wbMSE)
/// + 1-байтовая команда → готовые 11 байт для эфира:
/// wbMSE + 0x00 → 6D B6 43 CE 97 FE 42 7C E5 15 7D.
///
/// Структура: преамбула 71 0F 55, реверс адреса, CRC16-CCITT,
/// два прохода LFSR-скремблирования (0x3F и 0x25).
abstract final class RfPayloadEncoder {
  static const int _lfsrKeyPass1 = 0x3F;
  static const int _lfsrKeyPass2 = 0x25;
  static const List<int> _preamble = <int>[0x71, 0x0F, 0x55];

  /// Кодирует адрес (префикс) и пейлоад в эфирные байты.
  static Uint8List encode(List<int> address, List<int> payload) {
    final al = address.length;
    final pl = payload.length;
    final bs = al + 18 + pl + 2;
    final buf = List<int>.filled(bs, 0);

    buf[15] = _preamble[0];
    buf[16] = _preamble[1];
    buf[17] = _preamble[2];

    for (var i = 0; i < al; i++) {
      buf[al - 1 + 18 - i] = address[i] & 0xFF;
    }

    final d = al + 18;
    for (var i = 0; i < pl; i++) {
      buf[d + i] = payload[i] & 0xFF;
    }

    for (var j = 0; j < al + 3; j++) {
      buf[15 + j] = _bitReverse8(buf[15 + j]);
    }

    final crc = _crc16(address, payload);
    final cp = d + pl;
    buf[cp] = crc & 0xFF;
    buf[cp + 1] = (crc >> 8) & 0xFF;

    _lfsr(buf, al + 2 + pl, _lfsrExpand(_lfsrKeyPass1), 18);
    _lfsr(buf, bs, _lfsrExpand(_lfsrKeyPass2), 0);

    return Uint8List.fromList(buf.sublist(15));
  }

  /// Адрес + однобайтовая команда.
  static Uint8List encodeCommand(List<int> address, int commandByte) =>
      encode(address, <int>[commandByte & 0xFF]);

  /// Эфирный 8-байтовый префикс из сырого 5-байтового префикса API:
  /// первые 8 байт encode(address, 0x00).
  static String airPrefixHex(List<int> rawAddress) {
    final bytes = encodeCommand(rawAddress, 0x00);
    return bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  static int _bitReverse8(int v) {
    var x = v & 0xFF;
    var r = 0;
    for (var i = 0; i < 8; i++) {
      r = (r << 1) | (x & 1);
      x >>= 1;
    }
    return r;
  }

  static int _bitReverse16(int v) {
    var x = v & 0xFFFF;
    var r = 0;
    for (var i = 0; i < 16; i++) {
      r = (r << 1) | (x & 1);
      x >>= 1;
    }
    return r;
  }

  static int _crcStep(int v) {
    var x = v & 0xFFFF;
    for (var i = 0; i < 8; i++) {
      x = (x & 0x8000) != 0 ? ((x << 1) ^ 0x1021) & 0xFFFF : (x << 1) & 0xFFFF;
    }
    return x;
  }

  static int _crc16(List<int> addr, List<int> pay) {
    var c = 0xFFFF;
    for (var i = addr.length - 1; i >= 0; i--) {
      c = _crcStep(((addr[i] & 0xFF) << 8) ^ c);
    }
    for (final b in pay) {
      c = _crcStep(c ^ (_bitReverse8(b & 0xFF) << 8));
    }
    return (~_bitReverse16(c)) & 0xFFFF;
  }

  static List<int> _lfsrExpand(int k) => <int>[
        1,
        (k >> 5) & 1,
        (k >> 4) & 1,
        (k >> 3) & 1,
        (k >> 2) & 1,
        (k >> 1) & 1,
        k & 1,
      ];

  static void _lfsr(List<int> buf, int n, List<int> st, int off) {
    for (var i = 0; i < n; i++) {
      final s0 = st[0], s1 = st[1], s2 = st[2], s3 = st[3];
      final s4 = st[4], s5 = st[5], s6 = st[6];

      final v12 = s2 ^ s5;
      final v14 = s1 ^ s4;
      final v15 = s6 ^ s3;
      final v16 = v15 ^ s0;
      final v17 = v12 ^ s6;

      st[0] = v17;
      st[1] = v16;
      st[2] = v14;
      st[3] = v12;
      st[4] = s3 ^ v12;
      st[5] = v16 ^ s4;
      st[6] = v14 ^ s5;

      final dd = buf[i + off] & 0xFF;
      buf[i + off] = ((dd & 0x80) ^ ((v17 & 1) << 7)) |
          ((dd & 0x40) ^ ((v16 & 1) << 6)) |
          ((dd & 0x20) ^ ((v14 & 1) << 5)) |
          ((dd & 0x10) ^ ((v12 & 1) << 4)) |
          ((dd & 0x08) ^ ((v15 & 1) << 3)) |
          ((dd & 0x04) ^ ((s4 & 1) << 2)) |
          ((dd & 0x02) ^ ((s5 & 1) << 1)) |
          ((dd & 0x01) ^ (s6 & 1));
    }
  }
}
