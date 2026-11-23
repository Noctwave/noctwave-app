import 'package:flutter/foundation.dart';

import 'local_store.dart';

/// Реактивное состояние настроек: тема и акцент обновляют всё приложение
/// без перезапуска. Виджеты подписываются через [ListenableBuilder] /
/// [AnimatedBuilder].
class SettingsController extends ChangeNotifier {
  SettingsController(this._store) : _settings = _store.loadSettings();

  final LocalStore _store;
  AppSettings _settings;

  /// Доступ к хранилищу для страниц, работающих с профилями/ритмами.
  LocalStore get store => _store;

  AppSettings get settings => _settings;

  /// Сохраняет и уведомляет подписчиков.
  Future<void> update(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _store.saveSettings(next);
  }

  /// Перечитывает из хранилища (например, после импорта базы).
  void reload() {
    _settings = _store.loadSettings();
    notifyListeners();
  }
}
