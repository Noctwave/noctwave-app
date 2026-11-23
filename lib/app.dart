import 'package:material_ui/material_ui.dart';

import 'core/theme/noctwave_theme.dart';
import 'features/devices/devices_page.dart';
import 'features/profile/profile_page.dart';

/// Корневая навигация: две вкладки (ТЗ 2).
class NoctwaveApp extends StatelessWidget {
  const NoctwaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noctwave',
      debugShowCheckedModeBanner: false,
      theme: buildNoctwaveTheme(),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _pages = <Widget>[
    DevicesPage(),
    ProfilePage(),
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
