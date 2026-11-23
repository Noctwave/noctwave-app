import 'package:material_ui/material_ui.dart';

import '../../core/models/device_profile.dart';
import '../../core/theme/noctwave_theme.dart';
import '../control/control_page.dart';

/// Вкладка «Устройства» (ТЗ 3.2.1): сетка профилей + Empty State.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final List<DeviceProfile> _devices = <DeviceProfile>[];

  void _openDevice(DeviceProfile device) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ControlPage(device: device),
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NoctwavePalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: NoctwavePalette.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner,
                  color: NoctwavePalette.accentLow),
              title: const Text('Добавить по коду / QR'),
              subtitle: const Text('Однократный запрос к базе моделей'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addDemoProfile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_books_outlined,
                  color: NoctwavePalette.accentLow),
              title: const Text('Выбрать из оффлайн-базы'),
              subtitle: const Text('Готовые профили семейств устройств'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addDemoProfile();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _addDemoProfile() {
    // MVP-заготовка: полноценный импорт (API zlmicro + оффлайн-база)
    // подключается на следующем этапе; пока — эталонный профиль из ТЗ.
    setState(() {
      _devices.add(
        DeviceProfile(
          id: 'demo-${_devices.length + 1}',
          name: 'Модель #4923',
          barcode: '4923',
          broadcastPrefixHex: '6DB643CE97FE427C',
          manufacturerId: 65520,
          channels: const <DeviceChannel>[
            DeviceChannel(
              id: 'ch_vibe',
              name: 'Вибрация',
              type: ChannelType.vibrate,
              stopCmdHex: 'E5157D',
              intensityStepsHex: <String>[
                'E5157D', 'F41D7C', 'F7864E', 'E68E4F',
              ],
              presets: <PresetCommand>[
                PresetCommand(
                  id: 'p1', label: 'Слабо', cmdHex: 'F41D7C', icon: 'speed_1',
                ),
                PresetCommand(
                  id: 'p2', label: 'Средне', cmdHex: 'F7864E', icon: 'speed_2',
                ),
                PresetCommand(
                  id: 'p3', label: 'Максимум', cmdHex: 'E68E4F', icon: 'speed_3',
                ),
              ],
            ),
          ],
          createdAt: DateTime.now().toUtc(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Устройства'),
        actions: <Widget>[
          IconButton(
            onPressed: _showAddSheet,
            icon: const Icon(Icons.add),
            tooltip: 'Добавить устройство',
          ),
        ],
      ),
      body: _devices.isEmpty ? _buildEmptyState() : _buildGrid(),
      floatingActionButton: _devices.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _showAddSheet,
              backgroundColor: NoctwavePalette.accentLow,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.bluetooth_searching,
              size: 64,
              color: NoctwavePalette.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Пока нет устройств',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавьте устройство по коду с коробки\nили выберите готовый профиль.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NoctwavePalette.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Добавить по коду / QR'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _showAddSheet,
              icon: const Icon(Icons.library_books_outlined),
              label: const Text('Выбрать из оффлайн-базы'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: _devices.length,
      itemBuilder: (context, i) {
        final device = _devices[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openDevice(device),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.toys_outlined,
                      color: NoctwavePalette.accentLow, size: 28),
                  const Spacer(),
                  Text(
                    device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: device.channels
                        .map(
                          (ch) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: NoctwavePalette.accentLow
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              ch.name,
                              style: const TextStyle(
                                fontSize: 11,
                                color: NoctwavePalette.textSecondary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
