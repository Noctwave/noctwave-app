import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/storage/local_store.dart';
import '../../core/storage/settings_controller.dart';
import '../../core/theme/noctwave_theme.dart';
import 'settings_page.dart';

/// Вкладка «Профиль» — личный профиль пользователя: имя, пол, возраст,
/// аватар-заглушка (м/ж). Настройки вынесены на подстраницу.
/// Внизу — копирайт и версия (5 тапов по версии = Debug Mode).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.controller});

  final SettingsController controller;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _versionTaps = 0;

  AppSettings get _settings => widget.controller.settings;

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

  Future<void> _editName() async {
    final controller = TextEditingController(text: _settings.profileName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Имя'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _update(_settings.copyWith(profileName: name));
  }

  Future<void> _editAge() async {
    final controller =
        TextEditingController(text: _settings.profileAge.toString());
    final age = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Возраст'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text.trim())),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (age == null || age < 1 || age > 120) return;
    await _update(_settings.copyWith(profileAge: age));
  }

  @override
  Widget build(BuildContext context) {
    final colors = NoctwaveColors.of(context);
    final isFemale = _settings.profileGender == 'Женский';
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Профиль'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Настройки',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(controller: widget.controller),
                  ),
                );
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const SizedBox(height: 8),
            // Аватар-заглушка: человечек м/ж в зависимости от пола.
            Center(
              child: Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.15),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: Icon(
                  isFemale ? Icons.female : Icons.male,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _settings.profileName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: Icon(Icons.person_outline, color: colors.textSecondary),
                    title: const Text('Имя'),
                    trailing: Text(_settings.profileName,
                        style: TextStyle(color: colors.textSecondary)),
                    onTap: () => unawaited(_editName()),
                  ),
                  Divider(height: 1, color: colors.outline),
                  ListTile(
                    leading: Icon(Icons.wc_outlined, color: colors.textSecondary),
                    title: const Text('Пол'),
                    trailing: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment(value: 'Мужской', label: Text('М')),
                        ButtonSegment(value: 'Женский', label: Text('Ж')),
                      ],
                      selected: <String>{_settings.profileGender},
                      onSelectionChanged: (s) => unawaited(
                          _update(_settings.copyWith(profileGender: s.first))),
                    ),
                    onTap: null,
                  ),
                  Divider(height: 1, color: colors.outline),
                  ListTile(
                    leading: Icon(Icons.cake_outlined, color: colors.textSecondary),
                    title: const Text('Возраст'),
                    trailing: Text('${_settings.profileAge}',
                        style: TextStyle(color: colors.textSecondary)),
                    onTap: () => unawaited(_editAge()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Кнопка перехода в настройки.
            FilledButton.icon(
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Настройки приложения'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(controller: widget.controller),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            // Копирайт и версия внизу.
            Center(
              child: Column(
                children: <Widget>[
                  GestureDetector(
                    onTap: _onVersionTap,
                    child: Text(
                      'Noctwave 1.0.0',
                      style: TextStyle(color: colors.textSecondary, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '© 2026 Noctwave. Offline-first, без телеметрии.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
