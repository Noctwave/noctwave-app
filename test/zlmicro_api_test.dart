import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/data/known_devices.dart';
import 'package:noctwave_app/core/network/zlmicro_api.dart';

void main() {
  group('ZlmicroApi.parseProductResponse — реальный формат ответа', () {
    // Живой ответ API для barcode 4923 (проверено запросом).
    final realResponse = jsonDecode('''
    {
      "data": {
        "Title": "1635",
        "DeviceTitle": "AAGS079",
        "BarCode": "4923",
        "BroadcastPrefix": "77 62 4d 53 45",
        "Pics": "https://image.zlmicro.com/images/product/20230608/20230608134458286.png",
        "Qrcode": "https://image.zlmicro.com/images/product/qrcode/4923.png",
        "IsPrecise": 1,
        "FuncObj": {"classic": true, "music": true, "shake": true, "video": true}
      },
      "response": {"result": true, "errorCode": 10000, "msg": "Success"}
    }
    ''') as Map<String, dynamic>;

    test('парсит DeviceTitle, префикс и картинку из живого ответа', () {
      final profile = ZlmicroApi.parseProductResponse('4923', realResponse);
      expect(profile.name, 'AAGS079');
      expect(profile.barcode, '4923');
      // Сырой wbMSE (77624D5345) → эфирный префикс через get_rf_payload.
      expect(profile.broadcastPrefixHex, '6DB643CE97FE427C');
      expect(profile.localImagePath, contains('image.zlmicro.com'));
    });

    test('сырой префикс wbMSE даёт канал с 9 паттернами (0x00-0x09)', () {
      final profile = ZlmicroApi.parseProductResponse('4923', realResponse);
      expect(profile.channels.single.intensityStepsHex.length, 10);
      expect(profile.channels.single.intensityStepsHex[1], 'E49C6C');
      expect(profile.channels.single.stopCmdHex, 'E5157D');
    });

    test('пустой ответ даёт профиль-черновик с 9 паттернами', () {
      final profile =
          ZlmicroApi.parseProductResponse('1234', <String, dynamic>{});
      expect(profile.name, 'Модель #1234');
      expect(profile.broadcastPrefixHex, '6DB643CE97FE427C');
      expect(profile.channels.single.intensityStepsHex.length, 10);
      expect(profile.channels.single.presets.length, 9);
    });

    test('Title без DeviceTitle даёт Модель #Title', () {
      final profile = ZlmicroApi.parseProductResponse(
        '777',
        <String, dynamic>{
          'data': <String, dynamic>{'Title': '9999'},
        },
      );
      expect(profile.name, 'Модель #9999');
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
  });

  group('KnownDevices — проверенные семейства', () {
    test('двухканальное семейство: 2 канала по 10 ступеней', () {
      final family = KnownDevices.dualMotor();
      expect(family.prefixHex, '6DB643CE97FE427C');
      expect(family.channels.length, 2);
      for (final ch in family.channels) {
        expect(ch.intensityStepsHex.length, 10);
        expect(ch.presets.length, 9);
        expect(ch.stopCmdHex, ch.intensityStepsHex.first);
      }
    });

    test('стоп-команды каналов различаются (независимые каналы)', () {
      final family = KnownDevices.dualMotor();
      expect(family.channels[0].stopCmdHex,
          isNot(family.channels[1].stopCmdHex));
    });

    test('byPrefix находит семейства по эфирному префиксу', () {
      expect(KnownDevices.byPrefix('6db643ce97fe427c')?.id, 'single-6db6');
      expect(KnownDevices.byPrefix('6DB643CE97FE427C')?.id, 'single-6db6');
    });

    test('byPrefix: неизвестный префикс → null', () {
      expect(KnownDevices.byPrefix('AABBCCDDEEFF0011'), isNull);
    });

    test('одноканальное семейство: 9 паттернов общего канала', () {
      final family = KnownDevices.singleMotor();
      expect(family.channels.single.intensityStepsHex[1], 'E49C6C');
      expect(family.channels.single.intensityStepsHex[3], 'E68E4F');
    });
  });
}
