import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ble/rf_payload_encoder.dart';
import '../data/known_devices.dart';
import '../models/device_profile.dart';

/// Одноразовый импорт профиля устройства по коду с коробки (ТЗ 6.1).
///
/// Единственный сетевой запрос приложения:
/// GET http://lovespouse.zlmicro.com/index.php?g=App&m=Diyapp&a=getproductdetail&barcode={code}&userid=-1
///
/// Реальный формат ответа (проверено живым запросом для barcode 4923):
/// { "data": { "Title", "DeviceTitle", "BarCode", "BroadcastPrefix": "77 62 4d 53 45",
///   "Pics", "Qrcode", "FuncObj": {...}, "ClassicId": [...], "IsPrecise": 1 },
///   "response": { "result": true, "errorCode": 10000 } }
///
/// Команд в этом эндпоинте нет — они подбираются из известных семейств
/// по префиксу либо через Command Hunter.
class ZlmicroApi {
  ZlmicroApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration timeout = Duration(seconds: 8);

  static Uri endpointFor(String barcode) => Uri.http(
        'lovespouse.zlmicro.com',
        '/index.php',
        <String, String>{
          'g': 'App',
          'm': 'Diyapp',
          'a': 'getproductdetail',
          'barcode': barcode,
          'userid': '-1',
        },
      );

  /// Запрашивает модель по коду и парсит ответ в профиль.
  Future<DeviceProfile> fetchDevice(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) {
      throw const ImportException('Введите код с коробки устройства');
    }
    http.Response response;
    try {
      response = await _client.get(endpointFor(code)).timeout(timeout);
    } catch (_) {
      throw const ImportException(
        'Сервер недоступен. Выберите профиль из оффлайн-базы '
        'или создайте устройство вручную.',
      );
    }
    if (response.statusCode != 200) {
      throw ImportException(
        'Сервер вернул ошибку ${response.statusCode}. '
        'Попробуйте оффлайн-базу пресетов.',
      );
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      throw const ImportException('Не удалось разобрать ответ сервера');
    }
    final result = (json['response'] as Map<String, dynamic>?)?['result'];
    if (result == false) {
      throw const ImportException(
        'Устройство с таким кодом не найдено в базе. '
        'Проверьте код или выберите профиль из оффлайн-базы.',
      );
    }
    return parseProductResponse(code, json);
  }

  /// Парсит реальный JSON ответа zlmicro в DeviceProfile.
  static DeviceProfile parseProductResponse(
    String barcode,
    Map<String, dynamic> json,
  ) {
    final data = (json['data'] as Map<String, dynamic>?) ?? json;

    final title = (data['Title'] ?? '').toString().trim();
    final deviceTitle = (data['DeviceTitle'] ?? '').toString().trim();
    final name = deviceTitle.isNotEmpty
        ? deviceTitle
        : (title.isNotEmpty ? 'Модель #$title' : 'Модель #$barcode');

    // BroadcastPrefix приходит как "77 62 4d 53 45" — это СЫРОЙ префикс.
    // Эфирный префикс и команды считаются через get_rf_payload (Fastcon).
    final rawPrefix = (data['BroadcastPrefix'] ?? '').toString();
    final rawClean = rawPrefix.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    final rawBytes = <int>[
      for (var i = 0; i + 1 < rawClean.length; i += 2)
        int.parse(rawClean.substring(i, i + 2), radix: 16),
    ];

    final pics = (data['Pics'] ?? '').toString();

    // Эфирный префикс из сырого (wbMSE → 6DB643CE97FE427C).
    final airPrefix = rawBytes.length == 5
        ? RfPayloadEncoder.airPrefixHex(rawBytes)
        : (rawClean.length == 16 ? rawClean.toUpperCase() : '');

    // Каналы: для 5-байтового сырого префикса считаем на лету,
    // иначе подбираем проверенное семейство по эфирному префиксу.
    final family = KnownDevices.byPrefix(airPrefix);
    final channels = rawBytes.length == 5
        ? KnownDevices.channelsFromRawPrefix(rawBytes)
        : (family?.channels ?? KnownDevices.channelsFromRawPrefix(KnownDevices.rawWbMse));

    return DeviceProfile(
      id: 'import-$barcode-${DateTime.now().millisecondsSinceEpoch}',
      barcode: barcode,
      name: name,
      localImagePath: pics.isEmpty ? null : pics,
      broadcastPrefixHex:
          airPrefix.isEmpty ? '6DB643CE97FE427C' : airPrefix,
      manufacturerId: family?.manufacturerId ?? 0xFFF0,
      channels: channels,
      createdAt: DateTime.now().toUtc(),
    );
  }

  void dispose() => _client.close();
}

/// Ошибка импорта с сообщением для пользователя (ТЗ 6.1).
class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
