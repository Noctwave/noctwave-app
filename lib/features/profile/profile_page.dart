import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/ble/tx_log.dart';
import '../../core/models/device_profile.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/noctwave_theme.dart';
import '../debug/debug_page.dart';

/// Вкладка «Профиль» — локальные настройки с сохранением (ТЗ 3.2.5):
/// внешний вид, модули, приватность, экспорт/импорт базы, скрытый вход
/// в Debug Mode по 5 тапам по версии.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.store});

  final LocalStore store;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late AppSettings _settings = widget.store.loadSettings();
  int _versionTaps = 0;
  final TxLog _txLog = TxLog();

  Future<void> _update(AppSettings next) async {
    setState(() => _settings = next);
    await widget.store.saveSettings(next);
  }

  void _onVersionTap() {
    setState(() => _versionTaps++);
    if (_versionTaps >= 5 && !_settings.debugModeEnabled) {
      unawaited(_update(_settings.copyWith(debugModeEnabled: true)));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Режим разработчика активирован')),
      );
    }
  }

  Future<void> _exportBackup() async {
    try {
      final backup = widget.store.exportBackup();
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File('${dir.path}/noctwave-backup-$stamp.json');
      await file.writeAsString(backup.encode());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Экспортировано: ${file.path}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось экспортировать базу')),
      );
    }
  }

  Future<void> _importBackup() async {
    final controller = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Импорт базы из JSON'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Вставьте содержимое .json файла',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
    if (source == null || source.trim().isEmpty) return;
    try {
      final backup = AppBackup.decode(source);
      await widget.store.importBackup(backup);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _section('Внешний вид и отклик'),
          SwitchListTile(
            title: const Text('Тактильный отклик'),
            subtitle: const Text('Вибрация при переключении режимов и СТОП'),
            value: _settings.hapticsEnabled,
            onChanged: (v) =>
                unawaited(_update(_settings.copyWith(hapticsEnabled: v))),
          ),
          SwitchListTile(
            title: const Text('Пульсация интерфейса'),
            subtitle: const Text('Мягкое свечение в такт интенсивности'),
            value: _settings.pulseAnimation,
            onChanged: (v) =>
                unawaited(_update(_settings.copyWith(pulseAnimation: v))),
          ),
          _section('Функции и модули'),
          SwitchListTile(
            title: const Text('Таймер Кегеля'),
            value: _settings.kegelModule,
            onChanged: (v) =>
                unawaited(_update(_settings.copyWith(kegelModule: v))),
          ),
          SwitchListTile(
            title: const Text('Локальное видео'),
            value: _settings.videoModule,
            onChanged: (v) =>
                unawaited(_update(_settings.copyWith(videoModule: v))),
          ),
          SwitchListTile(
            title: const Text('Авто-СТОП при выходе'),
            subtitle: const Text('Останавливать устройство при выходе '
                'с экрана управления'),
            value: _settings.autoStopOnExit,
            onChanged: (v) =>
                unawaited(_update(_settings.copyWith(autoStopOnExit: v))),
          ),
          _section('Приватность и безопасность'),
          SwitchListTile(
            title: const Text('Громкость вниз = Экстренный СТОП'),
            subtitle: const Text('Работает и на OLED-замке'),
            value: _settings.volumeDownStop,
            onChanged: (v) =>
                unawaited(_update(_settings.copyWith(volumeDownStop: v))),
          ),
          SwitchListTile(
            title: const Text('Stealth Mode'),
            subtitle: const Text('Нейтральное имя приложения'),
            value: _settings.stealthMode,
            onChanged: (v) =>
                unawaited(_update(_settings.copyWith(stealthMode: v))),
          ),
          _section('Данные'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined,
                color: NoctwavePalette.textSecondary),
            title: const Text('Экспорт базы в JSON'),
            onTap: () => unawaited(_exportBackup()),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined,
                color: NoctwavePalette.textSecondary),
            title: const Text('Импорт базы из JSON'),
            onTap: () => unawaited(_importBackup()),
          ),
          _section('О приложении'),
          ListTile(
            title: const Text('Версия'),
            trailing: GestureDetector(
              onTap: _onVersionTap,
              child: const Text(
                '1.0.0',
                style: TextStyle(color: NoctwavePalette.textSecondary),
              ),
            ),
          ),
          if (_settings.debugModeEnabled) ...<Widget>[
            SwitchListTile(
              title: const Text('Режим разработчика'),
              subtitle: const Text(
                'HEX-инжектор · инспектор пакетов · тюнинг движка',
              ),
              value: _settings.debugModeEnabled,
              onChanged: (v) =>
                  unawaited(_update(_settings.copyWith(debugModeEnabled: v))),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined,
                  color: NoctwavePalette.accentLow),
              title: const Text('Открыть Debug Mode'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DebugPage(
                      store: widget.store,
                      txLog: _txLog,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            color: NoctwavePalette.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
