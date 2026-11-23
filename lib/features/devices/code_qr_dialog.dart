import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models/device_profile.dart';
import '../../core/network/zlmicro_api.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/noctwave_theme.dart';

/// Маленькое всплывающее окно «Код / QR» (ТЗ 3.2.2.1): поле ввода,
/// кнопка «Найти», кнопка запуска QR-сканера. При успехе показывает
/// инфу о модели и предлагает «Добавить» / «Отмена».
Future<DeviceProfile?> showCodeQrDialog(BuildContext context, LocalStore store) {
  return showDialog<DeviceProfile>(
    context: context,
    builder: (_) => _CodeQrDialog(store: store),
  );
}

class _CodeQrDialog extends StatefulWidget {
  const _CodeQrDialog({required this.store});

  final LocalStore store;

  @override
  State<_CodeQrDialog> createState() => _CodeQrDialogState();
}

class _CodeQrDialogState extends State<_CodeQrDialog> {
  final _codeController = TextEditingController();
  final _api = ZlmicroApi();

  bool _loading = false;
  bool _scanning = false;
  String? _error;
  DeviceProfile? _found;
  MobileScannerController? _scanner;

  @override
  void dispose() {
    _codeController.dispose();
    _api.dispose();
    unawaited(_scanner?.dispose());
    super.dispose();
  }

  Future<void> _find(String code) async {
    if (code.trim().isEmpty) {
      setState(() => _error = 'Введите код с коробки');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _found = null;
    });
    try {
      final profile = await _api.fetchDevice(code);
      if (!mounted) return;
      setState(() => _found = profile);
    } on ImportException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startScanner() {
    _scanner ??= MobileScannerController(
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode, BarcodeFormat.ean13],
    );
    setState(() => _scanning = true);
  }

  void _onBarcode(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    setState(() {
      _scanning = false;
      _codeController.text = digits;
    });
    unawaited(_find(digits));
  }

  Future<void> _add() async {
    final profile = _found;
    if (profile == null) return;
    final devices = widget.store.loadDevices()..add(profile);
    await widget.store.saveDevices(devices);
    if (!mounted) return;
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NoctwaveColors.of(context);
    return AlertDialog(
      backgroundColor: colors.surface,
      title: const Text('Добавить по коду / QR'),
      content: SizedBox(
        width: 320,
        child: _scanning ? _scannerView() : _formView(colors),
      ),
    );
  }

  Widget _scannerView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 240,
            child: MobileScanner(
              controller: _scanner!,
              onDetect: _onBarcode,
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() => _scanning = false),
          child: const Text('Назад к вводу кода'),
        ),
      ],
    );
  }

  Widget _formView(NoctwaveColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Код с коробки (например 4923)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: _find,
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: _loading ? null : () => _find(_codeController.text),
                child: _loading
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Найти'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Сканировать QR',
              onPressed: _startScanner,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: NoctwavePalette.stop, fontSize: 12)),
        ],
        if (_found != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_found!.name,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Префикс: ${_found!.broadcastPrefixHex}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: <Widget>[
                    for (final ch in _found!.channels)
                      Chip(label: Text(ch.name), visualDensity: VisualDensity.compact),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                  onPressed: () => unawaited(_add()),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ] else ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ),
        ],
      ],
    );
  }
}
