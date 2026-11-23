import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/data/builtin_devices.dart';
import '../../core/models/device_profile.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/noctwave_theme.dart';

/// Страница «Другие варианты» добавления устройства: выбор из встроенной
/// оффлайн-базы пресетов и ручное создание профиля (ТЗ 3.2.2.2–3).
class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key, required this.store});

  final LocalStore store;

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final _nameController = TextEditingController();
  final _prefixController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile(DeviceProfile profile) async {
    final devices = widget.store.loadDevices()..add(profile);
    await widget.store.saveDevices(devices);
    if (!mounted) return;
    Navigator.of(context).pop(profile);
  }

  Future<void> _createManual() async {
    final prefix = _prefixController.text.trim();
    if (prefix.length != 16 || !RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(prefix)) {
      setState(() => _error = 'Префикс — ровно 16 HEX-символов (8 байт)');
      return;
    }
    final profile = DeviceProfile(
      id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim().isEmpty
          ? 'Моё устройство'
          : _nameController.text.trim(),
      broadcastPrefixHex: prefix.toUpperCase(),
      manufacturerId: 0xFFF0,
      channels: <DeviceChannel>[
        const DeviceChannel(
          id: 'ch_1',
          name: 'Канал 1',
          type: ChannelType.generic,
          stopCmdHex: 'E5157D',
          intensityStepsHex: <String>['E5157D'],
        ),
      ],
      createdAt: DateTime.now().toUtc(),
    );
    await _saveProfile(profile);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NoctwaveColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Другие варианты')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _section('Оффлайн-база пресетов', colors),
          FutureBuilder<BuiltinDevices>(
            future: BuiltinDevices.load(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                children: <Widget>[
                  for (final template in snapshot.data!.profiles)
                    ListTile(
                      leading: Icon(Icons.bluetooth,
                          color: Theme.of(context).colorScheme.primary),
                      title: Text(template.name),
                      subtitle: Text(template.broadcastPrefixHex),
                      trailing: const Icon(Icons.add_circle_outline),
                      onTap: () =>
                          _saveProfile(BuiltinDevices.instantiate(template)),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          _section('Ручной профиль', colors),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'Название устройства',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _prefixController,
            decoration: const InputDecoration(
              hintText: '8-байтовый префикс HEX (16 символов)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: NoctwavePalette.stop)),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _createManual,
            child: const Text('Создать пустой профиль'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, NoctwaveColors colors) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
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
