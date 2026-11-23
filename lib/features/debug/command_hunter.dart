import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/ble/ble_advertiser.dart';
import '../../core/ble/tx_log.dart';
import '../../core/data/builtin_devices.dart';
import '../../core/models/device_profile.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/noctwave_theme.dart';

/// «Сыщик команд» (Command Hunter, ТЗ 4.6.1): пошаговый перебор
/// 3-байтовых команд по банкам с сохранением найденного в профиль.
class CommandHunter extends StatefulWidget {
  const CommandHunter({
    super.key,
    required this.store,
    required this.txLog,
    BleAdvertiserGateway? gateway,
  }) : _injectedGateway = gateway;

  final LocalStore store;
  final TxLog txLog;
  final BleAdvertiserGateway? _injectedGateway;

  @override
  State<CommandHunter> createState() => _CommandHunterState();
}

class _CommandHunterState extends State<CommandHunter> {
  late final BleAdvertiserGateway _gateway =
      widget._injectedGateway ?? MethodChannelBleAdvertiser();

  final _prefixController = TextEditingController();
  List<CommandBank> _banks = <CommandBank>[];
  int _bankIndex = 0;
  int _commandIndex = 0;
  bool _autoRun = false;
  int _autoPauseMs = 2000;
  Timer? _autoTimer;
  String _selectedDeviceId = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadBanks());
  }

  Future<void> _loadBanks() async {
    final builtin = await BuiltinDevices.load();
    if (!mounted) return;
    setState(() => _banks = builtin.commandBanks);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _prefixController.dispose();
    super.dispose();
  }

  List<DeviceProfile> get _devices => widget.store.loadDevices();

  DeviceProfile? get _selectedDevice {
    final list = _devices;
    for (final d in list) {
      if (d.id == _selectedDeviceId) return d;
    }
    return list.isEmpty ? null : list.first;
  }

  String get _prefix {
    final manual = _prefixController.text.trim().toUpperCase();
    if (manual.length == 16 && RegExp(r'^[0-9A-F]{16}$').hasMatch(manual)) {
      return manual;
    }
    return _selectedDevice?.broadcastPrefixHex ?? '';
  }

  CommandBank? get _bank =>
      _banks.isEmpty ? null : _banks[_bankIndex.clamp(0, _banks.length - 1)];

  String get _currentCommand {
    final bank = _bank;
    if (bank == null || bank.commands.isEmpty) return '';
    return bank.commands[_commandIndex.clamp(0, bank.commands.length - 1)];
  }

  Future<void> _sendCurrent() async {
    final prefix = _prefix;
    final command = _currentCommand;
    if (prefix.length != 16 || command.length != 6) return;
    widget.txLog.add(TxLogEntry(
      timestamp: DateTime.now(),
      prefixHex: prefix,
      commandHex: command,
      isStop: false,
      durationMs: 700,
    ));
    await _gateway.broadcastCommand(
      prefixHex: prefix,
      commandHex: command,
      manufacturerId: 0xFFF0,
      durationMs: 700,
    );
  }

  void _step(int delta) {
    final bank = _bank;
    if (bank == null || bank.commands.isEmpty) return;
    setState(() {
      _commandIndex = (_commandIndex + delta) % bank.commands.length;
      if (_commandIndex < 0) _commandIndex += bank.commands.length;
    });
    unawaited(_sendCurrent());
  }

  void _toggleAuto() {
    setState(() => _autoRun = !_autoRun);
    if (_autoRun) {
      _autoTimer?.cancel();
      _autoTimer = Timer.periodic(
        Duration(milliseconds: _autoPauseMs),
        (_) => _step(1),
      );
    } else {
      _autoTimer?.cancel();
      _autoTimer = null;
    }
  }

  /// «Работает! Сохранить в профиль» (ТЗ 4.6.1): присвоить имя, канал, тип.
  Future<void> _saveFound() async {
    final command = _currentCommand;
    final device = _selectedDevice;
    if (command.length != 6 || device == null) return;
    final nameController = TextEditingController(text: 'Найдено $command');
    String channelId = device.channels.firstOrNull?.id ?? '';
    String kind = 'preset';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Сохранить $command'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Название режима'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: channelId.isEmpty ? null : channelId,
                decoration: const InputDecoration(labelText: 'Канал'),
                items: <DropdownMenuItem<String>>[
                  for (final ch in device.channels)
                    DropdownMenuItem(value: ch.id, child: Text(ch.name)),
                ],
                onChanged: (v) => setDialogState(() => channelId = v ?? ''),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Тип'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'preset', child: Text('Пресет режима')),
                  DropdownMenuItem(value: 'step', child: Text('Ступень интенсивности')),
                ],
                onChanged: (v) => setDialogState(() => kind = v ?? 'preset'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Сохранить в профиль'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || channelId.isEmpty) return;

    final devices = widget.store.loadDevices();
    final idx = devices.indexWhere((d) => d.id == device.id);
    if (idx < 0) return;
    final json = devices[idx].toJson();
    final channels = (json['channels'] as List<dynamic>);
    for (final ch in channels) {
      final map = ch as Map<String, dynamic>;
      if (map['id'] != channelId) continue;
      if (kind == 'preset') {
        final presets = (map['presets'] as List<dynamic>?) ?? <dynamic>[];
        presets.add(<String, dynamic>{
          'id': 'found-${DateTime.now().millisecondsSinceEpoch}',
          'label': nameController.text.trim(),
          'cmdHex': command,
          'icon': 'spark',
          'isCustom': true,
        });
        map['presets'] = presets;
      } else {
        final steps = (map['intensityStepsHex'] as List<dynamic>).cast<String>();
        if (!steps.contains(command)) {
          steps.add(command);
          map['intensityStepsHex'] = steps;
        }
      }
    }
    devices[idx] = DeviceProfile.fromJson(json);
    await widget.store.saveDevices(devices);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$command сохранён в «${device.name}»')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bank = _bank;
    final devices = _devices;
    final selected = _selectedDevice;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (devices.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: selected?.id,
            decoration: const InputDecoration(
              labelText: 'Целевое устройство',
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<String>>[
              for (final d in devices)
                DropdownMenuItem(value: d.id, child: Text(d.name)),
            ],
            onChanged: (v) => setState(() => _selectedDeviceId = v ?? ''),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _prefixController,
          decoration: const InputDecoration(
            labelText: 'Произвольный префикс HEX (пусто = от устройства)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (bank != null) ...<Widget>[
          DropdownButtonFormField<int>(
            initialValue: _bankIndex,
            decoration: const InputDecoration(
              labelText: 'Банк команд',
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<int>>[
              for (var i = 0; i < _banks.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text('${_banks[i].name} (${_banks[i].commands.length})'),
                ),
            ],
            onChanged: (v) => setState(() {
              _bankIndex = v ?? 0;
              _commandIndex = 0;
            }),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  Text(
                    _currentCommand,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'Команда ${_commandIndex + 1} из ${bank.commands.length}',
                    style: const TextStyle(color: NoctwavePalette.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton.outlined(
                        tooltip: 'Предыдущая',
                        icon: const Icon(Icons.skip_previous),
                        onPressed: () => _step(-1),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.send),
                        label: const Text('Отправить'),
                        onPressed: () => unawaited(_sendCurrent()),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Следующая',
                        icon: const Icon(Icons.skip_next),
                        onPressed: () => _step(1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _autoRun
                        ? NoctwavePalette.accentHigh
                        : NoctwavePalette.accentLow,
                  ),
                  icon: Icon(_autoRun ? Icons.pause : Icons.play_arrow),
                  label: Text(_autoRun ? 'Стоп автоперебор' : 'Автоперебор'),
                  onPressed: _toggleAuto,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _autoPauseMs,
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem(value: 1000, child: Text('1 с')),
                  DropdownMenuItem(value: 2000, child: Text('2 с')),
                  DropdownMenuItem(value: 3000, child: Text('3 с')),
                  DropdownMenuItem(value: 5000, child: Text('5 с')),
                ],
                onChanged: (v) {
                  setState(() => _autoPauseMs = v ?? 2000);
                  if (_autoRun) {
                    _autoTimer?.cancel();
                    _autoTimer = Timer.periodic(
                      Duration(milliseconds: _autoPauseMs),
                      (_) => _step(1),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: NoctwavePalette.accentLow,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Работает! Сохранить в профиль'),
              onPressed: () => unawaited(_saveFound()),
            ),
          ),
        ] else
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
