import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ble/tx_log.dart';
import '../../core/models/device_profile.dart';
import '../../core/security/app_lock.dart';
import '../../core/storage/local_store.dart';
import '../../core/storage/settings_controller.dart';
import '../../core/theme/noctwave_theme.dart';
import '../debug/debug_page.dart';
import 'color_picker_dialog.dart';

/// Вкладка «Профиль» — локальные настройки (ТЗ 3.2.5): тема под систему,
/// акцент, модули, приватность (PIN/FaceID), экспорт/импорт базы,
/// скрытый вход в Debug Mode по 5 тапам по версии.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.controller});

  final SettingsController controller;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _versionTaps = 0;
  final TxLog _txLog = TxLog();
  final AppLock _lock = AppLock();

  AppSettings get _settings => widget.controller.settings;
  LocalStore get _store => widget.controller.store;

  Future<void> _update(AppSettings next) => widget.controller.update(next);

  void _onVersionTap() {
    setState(() => _versionTaps++);
    if (_versionTaps >= 5 && !_settings.debugModeEnabled) {
      unawaited(_update(_settings.copyWith(debugModeEnabled: true)));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Режим разработчика активирован')),
      );
    }
  }

  // ── Тема ────────────────────────────────────────────────────────────

  Widget _themeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<String>(
        segments: const <ButtonSegment<String>>[
          ButtonSegment(value: 'system', label: Text('Система'), icon: Icon(Icons.brightness_auto)),
          ButtonSegment(value: 'dark', label: Text('Тёмная'), icon: Icon(Icons.dark_mode)),
          ButtonSegment(value: 'light', label: Text('Светлая'), icon: Icon(Icons.light_mode)),
        ],
        selected: <String>{_settings.themeMode},
        onSelectionChanged: (s) => unawaited(_update(_settings.copyWith(themeMode: s.first))),
      ),
    );
  }

  // ── Акцентный цвет ──────────────────────────────────────────────────

  static const List<(String, int)> _accentPresets = <(String, int)>[
    ('Индиго', 0xFF6366F1),
    ('Фиолет', 0xFF8B5CF6),
    ('Бирюза', 0xFF14B8A6),
    ('Роза', 0xFFF43F5E),
    ('Янтарь', 0xFFF59E0B),
    ('Лайм', 0xFF84CC16),
  ];

  Widget _accentPicker() {
    final isCustom = !_accentPresets
        .any((p) => p.$2 == _settings.accentColorValue);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[
          for (final (name, value) in _accentPresets)
            _AccentDot(
              color: Color(value),
              label: name,
              selected: _settings.accentColorValue == value,
              onTap: () => unawaited(_update(_settings.copyWith(accentColorValue: value))),
            ),
          // Кастомный цвет: открывает HSV/HEX-пикер.
          _AccentDot(
            color: isCustom
                ? Color(_settings.accentColorValue)
                : NoctwaveColors.of(context).outline,
            label: 'Свой цвет',
            selected: isCustom,
            icon: isCustom ? null : Icons.colorize,
            onTap: () => unawaited(_pickCustomColor()),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomColor() async {
    final picked = await showColorPicker(
      context,
      Color(_settings.accentColorValue),
    );
    if (picked == null) return;
    await _update(_settings.copyWith(accentColorValue: picked.toARGB32()));
  }

  // ── PIN / биометрия ─────────────────────────────────────────────────

  Future<void> _setPin() async {
    final pin = await _pinDialog('Новый PIN (4–6 цифр)', confirm: true);
    if (pin == null) return;
    await _update(_settings.copyWith(appPinHash: AppLock.hashPin(pin)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN установлен')),
    );
  }

  Future<void> _removePin() async {
    await _update(_settings.copyWith(clearPinHash: true, biometricUnlock: false));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Блокировка отключена')),
    );
  }

  Future<void> _toggleBiometric(bool enable) async {
    if (!enable) {
      await _update(_settings.copyWith(biometricUnlock: false));
      return;
    }
    final available = await _lock.isBiometricAvailable();
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Биометрия недоступна на этом устройстве')),
      );
      return;
    }
    final ok = await _lock.authenticateBiometric();
    if (!ok) return;
    await _update(_settings.copyWith(biometricUnlock: true));
  }

  /// Диалог ввода PIN с подтверждением.
  Future<String?> _pinDialog(String title, {bool confirm = false}) async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: c1,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            if (confirm)
              TextField(
                controller: c2,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Повторите PIN'),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final p1 = c1.text.trim();
              if (p1.length < 4 || p1.length > 6 || int.tryParse(p1) == null) {
                return;
              }
              if (confirm && c2.text.trim() != p1) return;
              Navigator.pop(dialogContext, p1);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  // ── Экспорт / импорт ────────────────────────────────────────────────

  Future<void> _exportBackup() async {
    try {
      final backup = _store.exportBackup();
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${dir.path}/noctwave-backup-$stamp.json');
      await file.writeAsString(backup.encode());
      if (!mounted) return;
      // Системный share-лист: сохранить в Файлы, отправить и т.д.
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'application/json')],
          subject: 'Noctwave backup $stamp',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось экспортировать базу')),
      );
    }
  }

  Future<void> _importBackup() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (files.isEmpty) return;
    try {
      final bytes = await files.first.readAsBytes();
      final backup = AppBackup.decode(String.fromCharCodes(bytes));
      await _store.importBackup(backup);
      widget.controller.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Импортировано: ${backup.devices.length} устройств, '
            '${backup.patterns.length} ритмов',
          ),
        ),
      );
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Некорректный JSON')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NoctwaveColors.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _section('Внешний вид и отклик', colors),
            _themeSelector(),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text('Акцентный цвет',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            ),
            _accentPicker(),
            SwitchListTile(
              title: const Text('Тактильный отклик'),
              subtitle: const Text('Вибрация при переключении режимов и СТОП'),
              value: _settings.hapticsEnabled,
              onChanged: (v) => unawaited(_update(_settings.copyWith(hapticsEnabled: v))),
            ),
            SwitchListTile(
              title: const Text('Пульсация интерфейса'),
              subtitle: const Text('Мягкое свечение в такт интенсивности'),
              value: _settings.pulseAnimation,
              onChanged: (v) => unawaited(_update(_settings.copyWith(pulseAnimation: v))),
            ),
            _section('Функции и модули', colors),
            SwitchListTile(
              title: const Text('Таймер Кегеля'),
              value: _settings.kegelModule,
              onChanged: (v) => unawaited(_update(_settings.copyWith(kegelModule: v))),
            ),
            SwitchListTile(
              title: const Text('Авто-СТОП при выходе'),
              subtitle: const Text('Останавливать устройство при возврате '
                  'к списку устройств'),
              value: _settings.autoStopOnExit,
              onChanged: (v) => unawaited(_update(_settings.copyWith(autoStopOnExit: v))),
            ),
            _section('Приватность и безопасность', colors),
            SwitchListTile(
              title: const Text('Громкость вниз = Экстренный СТОП'),
              subtitle: const Text('Работает и на OLED-замке'),
              value: _settings.volumeDownStop,
              onChanged: (v) => unawaited(_update(_settings.copyWith(volumeDownStop: v))),
            ),
            ListTile(
              leading: Icon(Icons.pin_outlined, color: colors.textSecondary),
              title: Text(_settings.appPinHash == null ? 'Установить PIN' : 'Изменить PIN'),
              onTap: () => unawaited(_setPin()),
            ),
            if (_settings.appPinHash != null)
              ListTile(
                leading: Icon(Icons.lock_open_outlined, color: colors.textSecondary),
                title: const Text('Отключить блокировку'),
                onTap: () => unawaited(_removePin()),
              ),
            SwitchListTile(
              title: const Text('FaceID / TouchID'),
              subtitle: const Text('Разблокировка биометрией'),
              value: _settings.biometricUnlock,
              onChanged: (v) => unawaited(_toggleBiometric(v)),
            ),
            _section('Данные', colors),
            ListTile(
              leading: Icon(Icons.ios_share_outlined, color: colors.textSecondary),
              title: const Text('Экспорт базы в JSON'),
              subtitle: const Text('Сохранить в Файлы или отправить'),
              onTap: () => unawaited(_exportBackup()),
            ),
            ListTile(
              leading: Icon(Icons.file_open_outlined, color: colors.textSecondary),
              title: const Text('Импорт базы из JSON'),
              onTap: () => unawaited(_importBackup()),
            ),
            _section('О приложении', colors),
            ListTile(
              title: const Text('Версия'),
              trailing: GestureDetector(
                onTap: _onVersionTap,
                child: Text('1.0.0', style: TextStyle(color: colors.textSecondary)),
              ),
            ),
            if (_settings.debugModeEnabled) ...<Widget>[
              SwitchListTile(
                title: const Text('Режим разработчика'),
                subtitle: const Text('HEX-инжектор · инспектор пакетов · тюнинг движка'),
                value: _settings.debugModeEnabled,
                onChanged: (v) => unawaited(_update(_settings.copyWith(debugModeEnabled: v))),
              ),
              ListTile(
                leading: Icon(Icons.bug_report_outlined, color: Theme.of(context).colorScheme.primary),
                title: const Text('Открыть Debug Mode'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DebugPage(store: _store, txLog: _txLog),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String title, NoctwaveColors colors) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? NoctwaveColors.of(context).textPrimary : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : (icon != null
                  ? Icon(icon, color: NoctwaveColors.of(context).textPrimary, size: 20)
                  : null),
        ),
      ),
    );
  }
}
