import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:local_auth/local_auth.dart';

/// Блокировка входа в приложение (ТЗ 3.2.5 «Приватность»):
/// PIN-код и/или FaceID/TouchID. Хэш PIN хранится локально
/// (SHA-256 + соль), сам PIN нигде не сохраняется.
class AppLock {
  AppLock({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  static const String _salt = 'noctwave-pin-v1';

  /// SHA-256 хэш PIN с солью.
  static String hashPin(String pin) {
    final bytes = utf8.encode('$_salt:$pin');
    return crypto.sha256.convert(bytes).toString();
  }

  static bool verifyPin(String pin, String storedHash) =>
      hashPin(pin) == storedHash;

  /// Доступна ли биометрия на устройстве.
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      if (!canCheck || !supported) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Запрашивает FaceID/TouchID. Возвращает true при успехе.
  Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Разблокируйте Noctwave',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
