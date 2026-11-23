import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/security/app_lock.dart';

void main() {
  group('AppLock — PIN-хэширование (ТЗ 3.2.5)', () {
    test('hashPin детерминирован', () {
      expect(AppLock.hashPin('1234'), AppLock.hashPin('1234'));
    });

    test('разные PIN дают разные хэши', () {
      expect(AppLock.hashPin('1234'), isNot(AppLock.hashPin('1235')));
    });

    test('verifyPin: верный PIN проходит', () {
      final hash = AppLock.hashPin('482916');
      expect(AppLock.verifyPin('482916', hash), isTrue);
    });

    test('verifyPin: неверный PIN не проходит', () {
      final hash = AppLock.hashPin('482916');
      expect(AppLock.verifyPin('000000', hash), isFalse);
      expect(AppLock.verifyPin('', hash), isFalse);
    });

    test('хэш не содержит сам PIN', () {
      final hash = AppLock.hashPin('1234');
      expect(hash.contains('1234'), isFalse);
      expect(hash.length, 64); // SHA-256 hex
    });
  });
}
