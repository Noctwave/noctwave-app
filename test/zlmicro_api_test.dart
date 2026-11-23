import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/network/zlmicro_api.dart';

void main() {
  group('ZlmicroApi.parseProductResponse (ТЗ 6.1)', () {
    test('полный ответ парсится в профиль с эталонным префиксом', () {
      final json = jsonDecode('''
      {
        "code": 0,
        "data": {
          "productname": "Модель #4923",
          "prefix": "6D B6 43 CE 97 FE 42 7C"
        }
      }
      ''') as Map<String, dynamic>;
      final profile = ZlmicroApi.parseProductResponse('4923', json);
      expect(profile.barcode, '4923');
      expect(profile.name, 'Модель #4923');
      expect(profile.broadcastPrefixHex, '6DB643CE97FE427C');
      expect(profile.channels.single.stopCmdHex, 'E5157D');
      expect(profile.channels.single.intensityStepsHex.last, 'E68E4F');
    });

    test('пустой ответ даёт профиль-черновик с префиксом по умолчанию', () {
      final profile =
          ZlmicroApi.parseProductResponse('1234', <String, dynamic>{});
      expect(profile.name, 'Модель #1234');
      expect(profile.broadcastPrefixHex, ZlmicroApi.defaultPrefix);
    });

    test('endpoint содержит все параметры запроса из ТЗ', () {
      final uri = ZlmicroApi.endpointFor('4923');
      expect(uri.host, 'lovespouse.zlmicro.com');
      expect(uri.queryParameters['g'], 'App');
      expect(uri.queryParameters['m'], 'Diyapp');
      expect(uri.queryParameters['a'], 'getproductdetail');
      expect(uri.queryParameters['barcode'], '4923');
      expect(uri.queryParameters['userid'], '-1');
    });

    test('некорректный префикс заменяется эталонным', () {
      final profile = ZlmicroApi.parseProductResponse(
        '777',
        <String, dynamic>{'data': <String, dynamic>{'prefix': 'XYZ'}},
      );
      expect(profile.broadcastPrefixHex, ZlmicroApi.defaultPrefix);
    });
  });
}
