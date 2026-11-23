import 'package:material_ui/material_ui.dart';

import '../../core/theme/noctwave_theme.dart';

/// Вкладка «Профиль» — локальные настройки (ТЗ 3.2.5, MVP-каркас).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _haptics = true;
  bool _pulseAnimation = true;
  bool _volumeDownStop = true;
  bool _kegelModule = false;
  bool _videoModule = false;
  bool _debugMode = false;
  int _versionTaps = 0;

  void _onVersionTap() {
    setState(() => _versionTaps++);
    if (_versionTaps >= 5 && !_debugMode) {
      setState(() => _debugMode = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Режим разработчика активирован')),
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
            value: _haptics,
            onChanged: (v) => setState(() => _haptics = v),
          ),
          SwitchListTile(
            title: const Text('Пульсация интерфейса'),
            subtitle: const Text('Мягкое свечение в такт интенсивности'),
            value: _pulseAnimation,
            onChanged: (v) => setState(() => _pulseAnimation = v),
          ),
          _section('Функции и модули'),
          SwitchListTile(
            title: const Text('Таймер Кегеля'),
            value: _kegelModule,
            onChanged: (v) => setState(() => _kegelModule = v),
          ),
          SwitchListTile(
            title: const Text('Локальное видео'),
            value: _videoModule,
            onChanged: (v) => setState(() => _videoModule = v),
          ),
          _section('Приватность и безопасность'),
          SwitchListTile(
            title: const Text('Громкость вниз = Экстренный СТОП'),
            subtitle: const Text('Работает и на OLED-замке'),
            value: _volumeDownStop,
            onChanged: (v) => setState(() => _volumeDownStop = v),
          ),
          _section('Данные'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined,
                color: NoctwavePalette.textSecondary),
            title: const Text('Экспорт базы в JSON'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined,
                color: NoctwavePalette.textSecondary),
            title: const Text('Импорт базы из JSON'),
            onTap: () {},
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
          if (_debugMode)
            SwitchListTile(
              title: const Text('Режим разработчика'),
              subtitle: const Text(
                'Command Hunter · HEX-инжектор · инспектор пакетов',
              ),
              value: _debugMode,
              onChanged: (v) => setState(() => _debugMode = v),
            ),
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
