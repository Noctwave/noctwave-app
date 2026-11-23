import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/models/device_profile.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/noctwave_theme.dart';
import '../control/control_page.dart';
import 'add_device_page.dart';

/// Вкладка «Устройства» (ТЗ 3.2.1): сетка сохранённых профилей,
/// Empty State, добавление через [AddDevicePage], долгое нажатие —
/// меню карточки (переименовать, дублировать, удалить).
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.store});

  final LocalStore store;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<DeviceProfile> _devices = <DeviceProfile>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _devices = widget.store.loadDevices());
  }

  Future<void> _openAddPage() async {
    await Navigator.of(context).push<DeviceProfile>(
      MaterialPageRoute<DeviceProfile>(
        builder: (_) => AddDevicePage(store: widget.store),
      ),
    );
    _reload();
  }

  void _openDevice(DeviceProfile device) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ControlPage(device: device, store: widget.store),
      ),
    );
  }

  Future<void> _rename(DeviceProfile device) async {
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переименовать'),
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
    final json = device.toJson()..['name'] = name;
    final devices = widget.store.loadDevices();
    final idx = devices.indexWhere((d) => d.id == device.id);
    if (idx < 0) return;
    devices[idx] = DeviceProfile.fromJson(json);
    await widget.store.saveDevices(devices);
    _reload();
  }

  Future<void> _duplicate(DeviceProfile device) async {
    final json = device.toJson()
      ..['id'] = 'copy-${device.id}-${DateTime.now().millisecondsSinceEpoch}'
      ..['name'] = '${device.name} (копия)';
    final devices = widget.store.loadDevices()..add(DeviceProfile.fromJson(json));
    await widget.store.saveDevices(devices);
    _reload();
  }

  Future<void> _delete(DeviceProfile device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Удалить «${device.name}»?'),
        content: const Text('Профиль и записанные ритмы устройства '
            'будут удалены локально.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: NoctwavePalette.stop),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final devices =
        widget.store.loadDevices().where((d) => d.id != device.id).toList();
    await widget.store.saveDevices(devices);
    _reload();
  }

  void _showCardMenu(DeviceProfile device) {
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
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Переименовать'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_rename(device));
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Дублировать'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_duplicate(device));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: NoctwavePalette.stop),
              title: const Text('Удалить'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_delete(device));
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Устройства'),
        actions: <Widget>[
          IconButton(
            onPressed: _openAddPage,
            icon: const Icon(Icons.add),
            tooltip: 'Добавить устройство',
          ),
        ],
      ),
      body: _devices.isEmpty ? _buildEmptyState() : _buildGrid(),
      floatingActionButton: _devices.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _openAddPage,
              backgroundColor: Theme.of(context).colorScheme.primary,
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
            Icon(
              Icons.bluetooth_searching,
              size: 64,
              color: NoctwaveColors.of(context).textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Пока нет устройств',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Добавьте устройство по коду с коробки\nили выберите готовый профиль.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NoctwaveColors.of(context).textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openAddPage,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Добавить по коду / QR'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openAddPage,
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
            onLongPress: () => _showCardMenu(device),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Icon(Icons.toys_outlined,
                          color: Theme.of(context).colorScheme.primary, size: 28),
                      // Большая зона тапа (44×44), без ripple-анимации.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showCardMenu(device),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Icon(Icons.more_vert,
                                size: 22,
                                color: NoctwaveColors.of(context).textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              ch.name,
                              style: TextStyle(
                                fontSize: 11,
                                color: NoctwaveColors.of(context).textSecondary,
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
