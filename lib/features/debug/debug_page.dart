import 'package:material_ui/material_ui.dart';

import '../../core/ble/ble_advertiser.dart';
import '../../core/ble/love_spouse_codec.dart';
import '../../core/ble/tx_log.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/noctwave_theme.dart';
import 'command_hunter.dart';

/// Режим разработчика (ТЗ 4.6): HEX-инжектор, инспектор пакетов
/// и тюнинг BLE-движка. Команды рассылаются по каналам выбранного
/// устройства либо в произвольный префикс.
class DebugPage extends StatefulWidget {
  const DebugPage({
    super.key,
    required this.store,
    required this.txLog,
    BleAdvertiserGateway? gateway,
  }) : _injectedGateway = gateway;

  final LocalStore store;
  final TxLog txLog;
  final BleAdvertiserGateway? _injectedGateway;

  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  late final BleAdvertiserGateway _gateway =
      widget._injectedGateway ?? MethodChannelBleAdvertiser();

  final _prefixController = TextEditingController();
  final _commandController = TextEditingController();
  final _durationController = TextEditingController(text: '350');

  String _selectedDeviceId = '';

  @override
  void initState() {
    super.initState();
    widget.txLog.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    widget.txLog.removeListener(_onLogChanged);
    _prefixController.dispose();
    _commandController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (mounted) setState(() {});
  }

  List<({String id, String name, String prefix})> get _devices =>
      widget.store.loadDevices()
          .map((d) => (id: d.id, name: d.name, prefix: d.broadcastPrefixHex))
          .toList();

  ({String id, String name, String prefix})? get _selected {
    final list = _devices;
    for (final d in list) {
      if (d.id == _selectedDeviceId) return d;
    }
    return list.isEmpty ? null : list.first;
  }

  Future<void> _inject() async {
    var prefix = _prefixController.text.trim().toUpperCase();
    if (prefix.isEmpty) {
      prefix = _selected?.prefix ?? '';
    }
    final command = _commandController.text.trim().toUpperCase();
    final duration = int.tryParse(_durationController.text.trim()) ?? 350;
    if (prefix.length != 16 ||
        !RegExp(r'^[0-9A-F]{16}$').hasMatch(prefix) ||
        command.length != 6 ||
        !RegExp(r'^[0-9A-F]{6}$').hasMatch(command)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Префикс — 16 HEX, команда — 6 HEX символов'),
      ));
      return;
    }
    widget.txLog.add(TxLogEntry(
      timestamp: DateTime.now(),
      prefixHex: prefix,
      commandHex: command,
      isStop: false,
      durationMs: duration,
    ));
    try {
      await _gateway.broadcastCommand(
        prefixHex: prefix,
        commandHex: command,
        manufacturerId: 0xFFF0,
        durationMs: duration,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось отправить пакет'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Режим разработчика'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Сыщик команд'),
              Tab(text: 'HEX-инжектор'),
              Tab(text: 'Инспектор'),
              Tab(text: 'Тюнинг движка'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            CommandHunter(
              store: widget.store,
              txLog: widget.txLog,
              gateway: widget._injectedGateway,
            ),
            _injectorTab(),
            _inspectorTab(),
            _tuningTab(),
          ],
        ),
      ),
    );
  }

  /// Ручной HEX-инжектор (ТЗ 4.6.2).
  Widget _injectorTab() {
    final devices = _devices;
    final selected = _selected;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (devices.isNotEmpty) ...<Widget>[
          DropdownButtonFormField<String>(
            initialValue: selected?.id,
            decoration: const InputDecoration(
                labelText: 'Целевое устройство (префикс)', border: OutlineInputBorder()),
            items: <DropdownMenuItem<String>>[
              for (final d in devices)
                DropdownMenuItem(value: d.id, child: Text('${d.name} · ${d.prefix}')),
            ],
            onChanged: (v) => setState(() => _selectedDeviceId = v ?? ''),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _prefixController,
          decoration: const InputDecoration(
            labelText: 'Префикс HEX (16 символов, пусто = от устройства)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _commandController,
          decoration: const InputDecoration(
            labelText: 'Команда HEX (6 символов)',
            border: OutlineInputBorder(),
            hintText: 'Например E5157D (СТОП)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _durationController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Длительность передачи, мс',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _inject,
          icon: const Icon(Icons.send),
          label: const Text('Отправить пакет'),
        ),
        const SizedBox(height: 8),
        Text(
          'Превью пакета: ${_previewText()}',
          style: const TextStyle(
              color: NoctwavePalette.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  String _previewText() {
    final prefix =
        _prefixController.text.trim().toUpperCase();
    final command = _commandController.text.trim().toUpperCase();
    if (prefix.length != 16 || command.length != 6) {
      return 'заполните префикс и команду';
    }
    try {
      final uuids = LoveSpouseCodec.encodeIosUuids(prefix, command);
      return 'iOS UUID: ${uuids.join(' ')}';
    } on Exception {
      return 'неверный HEX';
    }
  }

  /// Инспектор пакетов (ТЗ 4.6.3): live-лог последних пакетов.
  Widget _inspectorTab() {
    final entries = widget.txLog.entries;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Text('${entries.length} записей (RAM, максимум 200)',
                  style: const TextStyle(color: NoctwavePalette.textSecondary)),
              const Spacer(),
              TextButton(
                onPressed: widget.txLog.clear,
                child: const Text('Очистить'),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text('Пакеты ещё не отправлялись',
                      style: TextStyle(color: NoctwavePalette.textSecondary)),
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: NoctwavePalette.outline, height: 1),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final time =
                        '${e.timestamp.hour.toString().padLeft(2, '0')}:'
                        '${e.timestamp.minute.toString().padLeft(2, '0')}:'
                        '${e.timestamp.second.toString().padLeft(2, '0')}';
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${e.rawHex}  ${e.isStop ? "· СТОП" : ""}',
                        style: const TextStyle(
                          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                        ),
                      ),
                      subtitle: Text(
                        '$time · ${e.durationMs} мс · iOS: ${e.iosServiceUuids.join(" ")}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Тюнинг BLE-движка (ТЗ 4.6.4).
  Widget _tuningTab() {
    final s = widget.store.loadSettings();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Параметры движка применяются к новым сессиям управления.',
          style: const TextStyle(color: NoctwavePalette.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _TuningField(
          label: 'burstDurationMs (по умолчанию 350)',
          value: s.burstDurationMs,
          onChanged: (v) => _saveTuning(burstDurationMs: v),
        ),
        _TuningField(
          label: 'stopBurstDurationMs (по умолчанию 700)',
          value: s.stopBurstDurationMs,
          onChanged: (v) => _saveTuning(stopBurstDurationMs: v),
        ),
        _TuningField(
          label: 'minTxIntervalMs (по умолчанию 180)',
          value: s.minTxIntervalMs,
          onChanged: (v) => _saveTuning(minTxIntervalMs: v),
        ),
      ],
    );
  }

  Future<void> _saveTuning({
    int? burstDurationMs,
    int? stopBurstDurationMs,
    int? minTxIntervalMs,
  }) async {
    await widget.store.saveSettings(widget.store.loadSettings().copyWith(
          burstDurationMs: burstDurationMs,
          stopBurstDurationMs: stopBurstDurationMs,
          minTxIntervalMs: minTxIntervalMs,
        ));
    if (mounted) setState(() {});
  }
}

class _TuningField extends StatelessWidget {
  const _TuningField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: value.toString());
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Сохранить',
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v > 0) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}
