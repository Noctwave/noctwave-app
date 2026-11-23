import 'package:material_ui/material_ui.dart';

import 'core/storage/local_store.dart';
import 'core/storage/settings_controller.dart';
import 'core/theme/noctwave_theme.dart';
import 'features/devices/devices_page.dart';
import 'features/lock/lock_screen.dart';
import 'features/profile/profile_page.dart';

/// Корневая навигация: две вкладки (ТЗ 2), тема под систему,
/// блокировка входа при заданном PIN/биометрии.
class NoctwaveApp extends StatelessWidget {
  const NoctwaveApp({super.key, required this.store});

  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final controller = SettingsController(store);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.settings;
        final accent = Color(s.accentColorValue);
        final themeMode = switch (s.themeMode) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        };
        return MaterialApp(
          title: 'Noctwave',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: buildNoctwaveTheme(colors: NoctwaveColors.light, accent: accent),
          darkTheme: buildNoctwaveTheme(colors: NoctwaveColors.dark, accent: accent),
          home: _LockGate(
            controller: controller,
            child: RootShell(controller: controller),
          ),
        );
      },
    );
  }
}

/// Обёртка блокировки: показывает LockScreen, пока вход не подтверждён.
class _LockGate extends StatefulWidget {
  const _LockGate({required this.controller, required this.child});

  final SettingsController controller;
  final Widget child;

  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> {
  bool _unlocked = false;

  bool get _needsLock {
    final s = widget.controller.settings;
    return s.appPinHash != null || s.biometricUnlock;
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsLock || _unlocked) return widget.child;
    return LockScreen(
      settings: widget.controller.settings,
      onUnlocked: () => setState(() => _unlocked = true),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.controller});

  final SettingsController controller;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  late final List<Widget> _pages = <Widget>[
    DevicesPage(store: widget.controller.store),
    ProfilePage(controller: widget.controller),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.bluetooth_outlined),
            selectedIcon: Icon(Icons.bluetooth),
            label: 'Устройства',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}
