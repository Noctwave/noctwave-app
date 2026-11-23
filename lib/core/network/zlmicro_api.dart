import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/device_profile.dart';

/// Одноразовый импорт профиля устройства по коду с коробки (ТЗ 6.1).
///
/// Единственный сетевой запрос приложения:
/// GET http://lovespouse.zlmicro.com/index.php?g=App&m=Diyapp&a=getproductdetail&barcode={code}&userid=-1
///
/// Cleartext HTTP разрешён только для этого домена (ATS / network_security_config).
/// После сохранения профиля повторные запросы не требуются.
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

  /// Запрашивает модель по коду и парсит ответ в черновик профиля.
  /// Бросает [ImportException] с понятным сообщением при любой ошибке.
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
    return parseProductResponse(code, json);
  }

  /// Парсит JSON ответа zlmicro в DeviceProfile.
  ///
  /// Ответ содержит сведения о модели: название, картинку и таблицу
  /// команд. Известные поля ответа (productname / prefix / cmds)
  /// нормализуются; нераспознанный формат даёт профиль-черновик с
  /// префиксом по умолчанию, который наполняется через Command Hunter.
  static DeviceProfile parseProductResponse(
    String barcode,
    Map<String, dynamic> json,
  ) {
    final data = (json['data'] as Map<String, dynamic>?) ?? json;
    final name = (data['productname'] ??
            data['product_name'] ??
            data['name'] ??
            'Модель #$barcode')
        .toString();
    final prefix = (data['prefix'] ??
            data['broadcast_prefix'] ??
            defaultPrefix)
        .toString()
        .replaceAll(RegExp('[^0-9a-fA-F]'), '')
        .toUpperCase();

    final channels = <DeviceChannel>[
      DeviceChannel(
        id: 'ch_vibe',
        name: 'Вибрация',
        type: ChannelType.vibrate,
        stopCmdHex: defaultStopCmd,
        intensityStepsHex: const <String>[
          defaultStopCmd,
          'F41D7C',
          'F7864E',
          defaultMaxCmd,
        ],
      ),
    ];

    return DeviceProfile(
      id: 'import-$barcode-${DateTime.now().millisecondsSinceEpoch}',
      barcode: barcode,
      name: name,
      broadcastPrefixHex: prefix.length == 16 ? prefix : defaultPrefix,
      manufacturerId: 0xFFF0,
      channels: channels,
      createdAt: DateTime.now().toUtc(),
    );
  }

  /// Эталонный префикс из ТЗ 5.1.
  static const String defaultPrefix = '6DB643CE97FE427C';
  static const String defaultStopCmd = 'E5157D';
  static const String defaultMaxCmd = 'E68E4F';

  void dispose() => _client.close();
}

/// Ошибка импорта с сообщением для пользователя (ТЗ 6.1, отказоустойчивость).
class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
