import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/data/builtin_devices.dart';
import '../../core/models/device_profile.dart';
import '../../core/network/zlmicro_api.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/noctwave_theme.dart';

/// Экран добавления устройства (ТЗ 3.2.2): три пути —
/// 1) импорт по коду / QR (интернет однократно, ТЗ 6.1);
/// 2) выбор из встроенной оффлайн-базы пресетов;
/// 3) ручное создание профиля (наполняется через Debug Mode).
class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key, required this.store});

  final LocalStore store;

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _prefixController = TextEditingController();
  final _api = ZlmicroApi();
  final _scannerController = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode, BarcodeFormat.ean13],
  );

  bool _loading = false;
  bool _scannerActive = false;
  String? _error;
  DeviceProfile? _preview;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _prefixController.dispose();
    _api.dispose();
    unawaited(_scannerController.dispose());
    super.dispose();
  }

  Future<void> _importByCode(String code) async {
    if (code.trim().isEmpty) {
      setState(() => _error = 'Введите код с коробки устройства');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
    });
    try {
      final profile = await _api.fetchDevice(code);
      if (!mounted) return;
      setState(() => _preview = profile);
    } on ImportException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile(DeviceProfile profile) async {
    final devices = widget.store.loadDevices()..add(profile);
    await widget.store.saveDevices(devices);
    if (!mounted) return;
    Navigator.of(context).pop(profile);
  }

  void _onBarcode(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    // QR может содержать сам код или ссылку с кодом.
    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    setState(() => _scannerActive = false);
    _codeController.text = digits;
    unawaited(_importByCode(digits));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить устройство')),
      body: _scannerActive ? _buildScanner() : _buildBody(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: <Widget>[
        MobileScanner(
          controller: _scannerController,
          onDetect: _onBarcode,
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Наведите камеру на QR-код / штрихкод',
                style: TextStyle(
                  color: NoctwavePalette.textPrimary,
                  backgroundColor: NoctwavePalette.background.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () => setState(() => _scannerActive = false),
                child: const Text('Закрыть сканер'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _section('1 · Импорт по коду / QR'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Код с коробки (например 4923)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: _importByCode,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Сканировать QR',
              onPressed: () => setState(() => _scannerActive = true),
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _loading ? null : () => _importByCode(_codeController.text),
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Найти модель (один запрос в сеть)'),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: NoctwavePalette.stop)),
        ],
        if (_preview != null) ...<Widget>[
          const SizedBox(height: 12),
          _PreviewCard(profile: _preview!, onSave: _saveProfile),
        ],
        const SizedBox(height: 24),
        _section('2 · Оффлайн-база пресетов'),
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
                    leading: const Icon(Icons.bluetooth,
                        color: NoctwavePalette.accentLow),
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
        _section('3 · Ручной профиль'),
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
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _createManual,
          child: const Text('Создать пустой профиль'),
        ),
      ],
    );
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

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
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

/// Превью найденной модели с кнопкой «Сохранить локально» (ТЗ 3.2.2.1).
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.profile, required this.onSave});

  final DeviceProfile profile;
  final Future<void> Function(DeviceProfile) onSave;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(profile.name,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Префикс: ${profile.broadcastPrefixHex}',
                style: const TextStyle(
                    color: NoctwavePalette.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: <Widget>[
                for (final ch in profile.channels)
                  Chip(label: Text(ch.name), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download_done_outlined),
                label: const Text('Сохранить локально'),
                onPressed: () => onSave(profile),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
