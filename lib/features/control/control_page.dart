import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/ble/ble_advertiser.dart';
import '../../core/ble/logging_gateway.dart';
import '../../core/ble/tx_log.dart';
import '../../core/ble/tx_scheduler.dart';
import '../../core/engine/pattern_engine.dart';
import '../../core/models/device_profile.dart';
import '../../core/storage/local_store.dart';
import '../../core/system/system_controls.dart';
import '../../core/theme/noctwave_theme.dart';
import 'autopilot_mode.dart';
import 'gesture_mode.dart';
import 'oled_lock_overlay.dart';
import 'rhythms_mode.dart';
import 'sensors_bridge.dart';
import 'sensors_mode.dart';

/// Экран управления устройством (ТЗ 3.2.3): переключатель режимов,
/// рабочая область (MVP — «Пульт»), OLED-замок и нижний док.
class ControlPage extends StatefulWidget {
  const ControlPage({
    super.key,
    required this.device,
    this.store,
    BleAdvertiserGateway? gateway,
    TxLog? txLog,
  })  : _injectedGateway = gateway,
        _injectedTxLog = txLog;

  final DeviceProfile device;
  final LocalStore? store;
  final BleAdvertiserGateway? _injectedGateway;
  final TxLog? _injectedTxLog;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  late final BleAdvertiserGateway _rawGateway =
      widget._injectedGateway ?? MethodChannelBleAdvertiser();

  late final TxLog _txLog = widget._injectedTxLog ?? TxLog();

  late final BleAdvertiserGateway _gateway =
      LoggingBleGateway(_rawGateway, _txLog);

  late final AppSettings _settings =
      widget.store?.loadSettings() ?? const AppSettings();

  late final TxScheduler _scheduler = TxScheduler(
    gateway: _gateway,
    config: TxSchedulerConfig(
      burstDurationMs: _settings.burstDurationMs,
      stopBurstDurationMs: _settings.stopBurstDurationMs,
      minTxIntervalMs: _settings.minTxIntervalMs,
    ),
  );

  final SystemControls _systemControls = SystemControls();

  int _modeIndex = 0;
  int _channelIndex = 0;
  bool _txActive = false;
  bool _oledLock = false;
  String? _lastCommandHex;
  DateTime? _sessionStart;
  Timer? _sessionTicker;

  final PatternRecorder _recorder = PatternRecorder();
  bool _recording = false;

  static const _modes = <String>['Пульт', 'Жест', 'Ритмы', 'Автопилот', 'Сенсоры'];

  /// Поток акселерометра для режима «Сенсоры» (sensors_plus).
  Stream<(double, double, double)>? _accelerometerEvents;
  bool _sensorsProbed = false;

  @override
  void initState() {
    super.initState();
    // «Громкость вниз» = экстренный СТОП (ТЗ 3.2.5), если включено.
    _systemControls.onVolumeDown = () {
      if (_settings.volumeDownStop) {
        unawaited(_emergencyStop());
      }
    };
  }

  /// Ленивая инициализация акселерометра: сенсор открывается только при
  /// первом входе в режим «Сенсоры» (не держим сенсор зря).
  Future<void> _ensureSensors() async {
    if (_sensorsProbed) return;
    _sensorsProbed = true;
    try {
      await initSensors();
      _accelerometerEvents = sensorBridge?.accelerometerEvents;
    } catch (_) {
      // sensors_plus недоступен (desktop/тесты) — режим покажет заглушку.
      _accelerometerEvents = null;
    }
    if (mounted) setState(() {});
  }

  DeviceChannel? get _channel {
    final channels = widget.device.channels;
    if (channels.isEmpty) return null;
    return channels[_channelIndex.clamp(0, channels.length - 1)];
  }

  @override
  void dispose() {
    _sessionTicker?.cancel();
    _systemControls.dispose();
    unawaited(_systemControls.setKeepScreenOn(false));
    unawaited(_scheduler.dispose());
    super.dispose();
  }

  void _haptic(HapticFeedbackType type) {
    if (!_settings.hapticsEnabled) return;
    switch (type) {
      case HapticFeedbackType.light:
        unawaited(HapticFeedback.lightImpact());
      case HapticFeedbackType.medium:
        unawaited(HapticFeedback.mediumImpact());
      case HapticFeedbackType.heavy:
        unawaited(HapticFeedback.heavyImpact());
    }
  }

  void _startSession() {
    _sessionStart ??= DateTime.now();
    _sessionTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  String _sessionTime() {
    final start = _sessionStart;
    if (start == null) return '00:00';
    final elapsed = DateTime.now().difference(start);
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _sendCommand(String commandHex) async {
    final channel = _channel;
    if (channel == null) return;
    _startSession();
    _recorder.record(channel.id, commandHex);
    await _scheduler.sendBurstCommand(
      prefixHex: widget.device.broadcastPrefixHex,
      commandHex: commandHex,
      manufacturerId: widget.device.manufacturerId,
    );
    if (!mounted) return;
    setState(() {
      _txActive = true;
      _lastCommandHex = commandHex;
    });
    // Индикатор TX гаснет после burst-окна.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _txActive = false);
    });
  }

  /// Динамическая команда из режимов Жест/Автопилот (ТЗ 5.4.2):
  /// квантование u → ступень, троттлинг и дедупликация — в планировщике.
  Future<void> _sendDynamic(String channelId, double u) async {
    final channel = widget.device.channels
        .where((c) => c.id == channelId)
        .firstOrNull;
    if (channel == null) return;
    _startSession();
    final cmd = TxScheduler.quantize(
      u: u,
      intensityStepsHex: channel.intensityStepsHex,
      stopCmdHex: channel.stopCmdHex,
    );
    _recorder.record(channel.id, cmd);
    await _scheduler.updateDynamicCommand(
      prefixHex: widget.device.broadcastPrefixHex,
      commandHex: cmd,
      manufacturerId: widget.device.manufacturerId,
    );
    if (!mounted) return;
    setState(() => _lastCommandHex = cmd);
  }

  /// Команда из плеера ритмов: уже готовый HEX, burst.
  Future<void> _sendPatternCommand(String channelId, String cmdHex) async {
    final channel = widget.device.channels
        .where((c) => c.id == channelId)
        .firstOrNull;
    if (channel == null) return;
    await _sendCommand(cmdHex);
  }

  /// REC в доке (ТЗ 4.3): запись/остановка записи сессии.
  void _toggleRecording() {
    if (_recording) {
      _finishRecording();
      return;
    }
    _haptic(HapticFeedbackType.medium);
    _recorder.start();
    setState(() => _recording = true);
  }

  Future<void> _finishRecording() async {
    final pattern = _recorder.finish(
      id: 'rec-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Сессия ${DateTime.now().hour.toString().padLeft(2, '0')}:'
          '${DateTime.now().minute.toString().padLeft(2, '0')}',
      deviceId: widget.device.id,
    );
    setState(() => _recording = false);
    if (pattern.events.isEmpty) return;
    final store = widget.store;
    if (store == null) return;
    // Имя можно уточнить сразу после записи (ТЗ 4.3).
    final controller = TextEditingController(text: pattern.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Сохранить ритм'),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отбросить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final json = pattern.toJson()..['name'] = name;
    final all = store.loadPatterns()..add(RecordedPattern.fromJson(json));
    await store.savePatterns(all);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ритм «$name» сохранён (${pattern.events.length} событий)')),
    );
  }

  /// Сохранить зацикленный жест в «Ритмы» (ТЗ 4.2).
  Future<void> _saveGestureToRhythms(List<GestureSample> samples) async {
    final store = widget.store;
    if (store == null || samples.isEmpty) return;
    final channel = _channel;
    if (channel == null) return;
    final events = <PatternEvent>[];
    String? lastCmd;
    for (final s in samples) {
      final cmd = TxScheduler.quantize(
        u: s.u1,
        intensityStepsHex: channel.intensityStepsHex,
        stopCmdHex: channel.stopCmdHex,
      );
      if (cmd == lastCmd) continue; // дедуп по квантованным ступеням
      lastCmd = cmd;
      events.add(PatternEvent(atMs: s.tMs, channelId: channel.id, cmdHex: cmd));
    }
    final pattern = RecordedPattern(
      id: 'gesture-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Жест ${DateTime.now().hour.toString().padLeft(2, '0')}:'
          '${DateTime.now().minute.toString().padLeft(2, '0')}',
      deviceId: widget.device.id,
      durationMs: samples.last.tMs,
      events: events,
    );
    final all = store.loadPatterns()..add(pattern);
    await store.savePatterns(all);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Жест сохранён в «Ритмы» (${events.length} событий)')),
    );
  }

  Future<void> _emergencyStop() async {
    final channel = _channel;
    if (channel == null) return;
    _haptic(HapticFeedbackType.heavy); // усиленный двойной импульс
    unawaited(HapticFeedback.vibrate());
    await _scheduler.stop(
      prefixHex: widget.device.broadcastPrefixHex,
      stopCmdHex: channel.stopCmdHex,
      manufacturerId: widget.device.manufacturerId,
    );
    if (!mounted) return;
    setState(() {
      _txActive = true;
      _lastCommandHex = channel.stopCmdHex;
      _sessionStart = null;
      _sessionTicker?.cancel();
      _sessionTicker = null;
    });
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _txActive = false);
    });
  }

  Future<void> _holdBoostStart() async {
    final channel = _channel;
    if (channel == null) return;
    _haptic(HapticFeedbackType.medium);
    await _sendCommand(channel.intensityStepsHex.last);
  }

  Future<void> _holdBoostRelease() async {
    final channel = _channel;
    if (channel == null) return;
    await _sendCommand(_lastCommandHex ?? channel.stopCmdHex);
  }

  Future<bool> _onWillPop() async {
    // При выходе опционально шлём СТОП (ТЗ 3.2.3).
    await _emergencyStop();
    return true;
  }

  void _toggleOledLock() {
    setState(() => _oledLock = !_oledLock);
    // Wakelock: экран не гаснет, пока активен OLED-замок (ТЗ 3.2.4).
    unawaited(_systemControls.setKeepScreenOn(_oledLock));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final pop = await _onWillPop();
        if (pop && mounted && context.mounted) Navigator.of(context).pop();
      },
      child: Stack(
        children: <Widget>[
          Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  if (await _onWillPop() && mounted && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              title: Text(widget.device.name),
              actions: <Widget>[
                IconButton(
                  tooltip: 'OLED-замок',
                  icon: const Icon(Icons.dark_mode_outlined),
                  onPressed: _toggleOledLock,
                ),
                IconButton(
                  tooltip: 'Настройки профиля',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {},
                ),
              ],
            ),
            body: Column(
              children: <Widget>[
                _modeChips(),
                if (widget.device.channels.length > 1) _channelTabs(),
                Expanded(
                  child: switch (_modeIndex) {
                    0 => _remoteMode(),
                    1 => GestureMode(
                        device: widget.device,
                        onCommand: (channelId, u) =>
                            unawaited(_sendDynamic(channelId, u)),
                        onSaveToRhythms: (samples) =>
                            unawaited(_saveGestureToRhythms(samples)),
                      ),
                    2 => widget.store == null
                        ? _placeholderMode('Ритмы')
                        : RhythmsMode(
                            device: widget.device,
                            store: widget.store!,
                            onCommand: (channelId, cmdHex) =>
                                unawaited(_sendPatternCommand(channelId, cmdHex)),
                          ),
                    3 => AutopilotMode(
                        onSample: (u) {
                          final channel = _channel;
                          if (channel != null) {
                            unawaited(_sendDynamic(channel.id, u));
                          }
                        },
                      ),
                    4 => _accelerometerEvents == null
                        ? _placeholderMode('Сенсоры (акселерометр недоступен)')
                        : SensorsMode(
                            onSample: (u) {
                              final channel = _channel;
                              if (channel != null) {
                                unawaited(_sendDynamic(channel.id, u));
                              }
                            },
                            accelerometerEvents: _accelerometerEvents!,
                          ),
                    _ => _placeholderMode(_modes[_modeIndex]),
                  },
                ),
                _dock(),
              ],
            ),
          ),
          if (_oledLock)
            OledLockOverlay(
              modeLabel: _modes[_modeIndex],
              txActive: _txActive,
              onUnlock: _toggleOledLock,
              onVolumeStop: _emergencyStop,
            ),
        ],
      ),
    );
  }

  Widget _modeChips() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _modes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ChoiceChip(
          label: Text(_modes[i]),
          selected: _modeIndex == i,
          onSelected: (_) {
            _haptic(HapticFeedbackType.light);
            setState(() => _modeIndex = i);
            if (i == 4) unawaited(_ensureSensors());
          },
        ),
      ),
    );
  }

  Widget _channelTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < widget.device.channels.length; i++) ...<Widget>[
            ChoiceChip(
              label: Text(widget.device.channels[i].name),
              selected: _channelIndex == i,
              onSelected: (_) => setState(() => _channelIndex = i),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _remoteMode() {
    final channel = _channel;
    if (channel == null) {
      return const Center(child: Text('У устройства нет каналов'));
    }
    final steps = channel.intensityStepsHex
        .skip(1) // индекс 0 — стоп, отдельная кнопка
        .toList();
    return Column(
      children: <Widget>[
        Expanded(
          child: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: <Widget>[
              for (var i = 0; i < steps.length; i++)
                _ModeTile(
                  label: 'Режим ${i + 1}',
                  sublabel: steps[i],
                  active: _lastCommandHex == steps[i],
                  intensity: (i + 1) / steps.length,
                  onTap: () {
                    _haptic(HapticFeedbackType.light);
                    unawaited(_sendCommand(steps[i]));
                  },
                ),
              for (final preset in channel.presets)
                _ModeTile(
                  label: preset.label,
                  sublabel: preset.cmdHex,
                  active: _lastCommandHex == preset.cmdHex,
                  intensity: 0.5,
                  onTap: () {
                    _haptic(HapticFeedbackType.light);
                    unawaited(_sendCommand(preset.cmdHex));
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: GestureDetector(
              // Hold-to-Boost (ТЗ 4.1): удержание — максимум,
              // отпускание — предыдущая активная команда.
              onLongPressStart: (_) => unawaited(_holdBoostStart()),
              onLongPressEnd: (_) => unawaited(_holdBoostRelease()),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: NoctwavePalette.accentHigh,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.bolt),
                label: const Text('Hold-to-Boost'),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholderMode(String mode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.construction_outlined,
              size: 48, color: NoctwavePalette.textSecondary),
          const SizedBox(height: 12),
          Text('Режим «$mode» — Этап 2',
              style: const TextStyle(color: NoctwavePalette.textSecondary)),
        ],
      ),
    );
  }

  /// Закреплённый нижний док (ТЗ 3.2.3): TX · REC · СТОП.
  Widget _dock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: NoctwavePalette.surface,
        border: Border(top: BorderSide(color: NoctwavePalette.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _txActive
                            ? NoctwavePalette.accentHigh
                            : NoctwavePalette.textSecondary.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'TX',
                      style: TextStyle(
                        color: _txActive
                            ? NoctwavePalette.accentHigh
                            : NoctwavePalette.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _sessionTime(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: NoctwavePalette.textSecondary,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _recording
                    ? NoctwavePalette.stop.withValues(alpha: 0.2)
                    : NoctwavePalette.surface,
                side: BorderSide(
                  color: _recording
                      ? NoctwavePalette.stop
                      : NoctwavePalette.outline,
                ),
              ),
              icon: Icon(
                _recording ? Icons.stop_circle : Icons.fiber_manual_record,
                color: NoctwavePalette.stop,
                size: 16,
              ),
              label: Text(_recording ? 'STOP REC' : 'REC'),
              onPressed: _toggleRecording,
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: NoctwavePalette.stop,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 16,
                ),
              ),
              icon: const Icon(Icons.stop),
              label: const Text(
                'СТОП',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () => unawaited(_emergencyStop()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Плитка режима пульта с динамическим акцентом по интенсивности.
class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.sublabel,
    required this.active,
    required this.intensity,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final bool active;
  final double intensity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = NoctwavePalette.accentForIntensity(intensity);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: NoctwavePalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? accent : NoctwavePalette.outline,
          width: active ? 1.5 : 1,
        ),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 16,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: active ? accent : NoctwavePalette.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sublabel,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    color: NoctwavePalette.textSecondary,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Типы тактильного отклика (ТЗ 3.1 Haptics).
enum HapticFeedbackType { light, medium, heavy }
