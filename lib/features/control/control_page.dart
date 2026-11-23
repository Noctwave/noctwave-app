import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/ble/ble_advertiser.dart';
import '../../core/ble/channel_mixer.dart';
import '../../core/ble/logging_gateway.dart';
import '../../core/ble/tx_log.dart';
import '../../core/ble/tx_scheduler.dart';
import '../../core/engine/pattern_engine.dart';
import '../../core/models/device_profile.dart';
import '../../core/storage/local_store.dart';
import '../../core/system/lifecycle_watcher.dart';
import '../../core/system/system_controls.dart';
import '../../core/theme/noctwave_theme.dart';
import 'autopilot_mode.dart';
import 'gesture_mode.dart';
import 'kegel_mode.dart';
import 'media_mode.dart';
import 'mic_mode.dart';
import 'oled_lock_overlay.dart';
import 'pulsing_active.dart';
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

  /// Непрерывная поканальная ротация: моторы не сбрасывают друг друга.
  late final ChannelMixer _mixer = ChannelMixer(
    gateway: _gateway,
    prefixHex: widget.device.broadcastPrefixHex,
    manufacturerId: widget.device.manufacturerId,
  );

  /// Текущая команда каждого канала (для подсветки плиток и записи).
  final Map<String, String> _channelCommands = <String, String>{};

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

  /// Список режимов: базовые + опциональные по настройкам Профиля (ТЗ 2).
  /// Музыка и видео объединены в один режим «Медиа» — суть одна:
  /// локальный файл управляет устройством через анализ звука.
  List<String> get _modes => <String>[
        'Пульт',
        'Жест',
        'Ритмы',
        'Автопилот',
        'Сенсоры',
        'Микрофон',
        'Медиа',
        if (_settings.kegelModule) 'Кегель',
      ];

  /// Поток акселерометра для режима «Сенсоры» (sensors_plus).
  Stream<(double, double, double)>? _accelerometerEvents;
  bool _sensorsProbed = false;

  late final LifecycleWatcher _lifecycle = LifecycleWatcher(
    onBackground: _onAppBackground,
    onForeground: _onAppForeground,
  );

  /// Шла ли передача в момент сворачивания.
  bool _wasTransmitting = false;

  /// Тихий индикатор в шапке: передача прервана сворачиванием.
  bool _showBackgroundHint = false;

  @override
  void initState() {
    super.initState();
    // «Громкость вниз» = экстренный СТОП (ТЗ 3.2.5), если включено.
    _systemControls.onVolumeDown = () {
      if (_settings.volumeDownStop) {
        unawaited(_emergencyStop());
      }
    };
    _lifecycle.start();
    for (final ch in widget.device.channels) {
      _mixer.registerStop(ch.id, ch.stopCmdHex);
    }
  }

  /// iOS: сворачивание или блокировка экрана переносит ServiceUUIDs в
  /// overflow area — пакет становится нечитаемым (ТЗ 5.3). Немедленно
  /// останавливаем устройство, если передача шла. Вместо назойливого
  /// snackbar — тихий индикатор в шапке, который гаснет тапом.
  void _onAppBackground() {
    _wasTransmitting = _lastCommandHex != null && _lastCommandHex != _channel?.stopCmdHex;
    if (_wasTransmitting) {
      unawaited(_emergencyStop());
    }
    if (!_oledLock && mounted) {
      setState(() => _showBackgroundHint = true);
    }
  }

  void _onAppForeground() {
    // Индикатор остаётся, пока пользователь его не скроет тапом.
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
    _lifecycle.dispose();
    _systemControls.dispose();
    unawaited(_systemControls.setKeepScreenOn(false));
    unawaited(_mixer.dispose());
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

  /// Пульт: команда только выбранного канала. Остальные каналы продолжают
  /// вещать свою прежнюю команду (микшер не сбрасывает их).
  Future<void> _sendCommand(String commandHex) async {
    final channel = _channel;
    if (channel == null) return;
    _startSession();
    _recorder.record(channel.id, commandHex);
    _channelCommands[channel.id] = commandHex;
    _mixer.setCommand(channel.id, commandHex);
    if (!mounted) return;
    setState(() {
      _txActive = true;
      _lastCommandHex = commandHex;
    });
  }

  /// Не-пульт режимы (Жест/Автопилот/Сенсоры/Микрофон/Медиа/Кегель):
  /// один уровень u применяется СРАЗУ ко всем моторам.
  void _sendToAll(double u) {
    _startSession();
    for (final ch in widget.device.channels) {
      final cmd = TxScheduler.quantize(
        u: u,
        intensityStepsHex: ch.intensityStepsHex,
        stopCmdHex: ch.stopCmdHex,
      );
      _recorder.record(ch.id, cmd);
      _channelCommands[ch.id] = cmd;
      _mixer.setCommand(ch.id, cmd);
    }
    if (!mounted) return;
    setState(() => _txActive = true);
  }

  /// Команда конкретного канала из жеста (2D) или плеера ритмов.
  void _sendChannel(String channelId, String cmdHex) {
    _startSession();
    _recorder.record(channelId, cmdHex);
    _channelCommands[channelId] = cmdHex;
    _mixer.setCommand(channelId, cmdHex);
    if (!mounted) return;
    setState(() {
      _txActive = true;
      _lastCommandHex = cmdHex;
    });
  }

  /// Динамический уровень для одного канала (жест 2D).
  void _sendDynamic(String channelId, double u) {
    final channel = widget.device.channels
        .where((c) => c.id == channelId)
        .firstOrNull;
    if (channel == null) return;
    final cmd = TxScheduler.quantize(
      u: u,
      intensityStepsHex: channel.intensityStepsHex,
      stopCmdHex: channel.stopCmdHex,
    );
    _sendChannel(channelId, cmd);
  }

  /// Команда из плеера ритмов: готовый HEX для канала.
  void _sendPatternCommand(String channelId, String cmdHex) {
    _sendChannel(channelId, cmdHex);
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
    // Один тактильный импульс на СТОП (без двойной вибрации).
    _haptic(HapticFeedbackType.heavy);
    _channelCommands.clear();
    await _mixer.stopAll();
    if (!mounted) return;
    setState(() {
      _txActive = true;
      _lastCommandHex = _channel?.stopCmdHex;
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
    _sendCommand(channel.intensityStepsHex.last);
  }

  Future<void> _holdBoostRelease() async {
    final channel = _channel;
    if (channel == null) return;
    _sendCommand(_channelCommands[channel.id] ?? channel.stopCmdHex);
  }

  /// Выход из управления: сразу закрываем экран, СТОП шлём в фоне.
  void _exitControl() {
    unawaited(_mixer.stopAll());
    if (mounted) Navigator.of(context).pop();
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
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitControl();
      },
      child: Stack(
        children: <Widget>[
          Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _exitControl,
              ),
              title: Text(widget.device.name),
              actions: <Widget>[
                IconButton(
                  tooltip: 'OLED-замок — держит экран активным',
                  icon: const Icon(Icons.dark_mode_outlined),
                  onPressed: _toggleOledLock,
                ),
                IconButton(
                  tooltip: 'Устройство',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _showDeviceMenu,
                ),
              ],
            ),
            body: Column(
              children: <Widget>[
                if (_showBackgroundHint) _backgroundHintBar(),
                _modeChips(),
                if (widget.device.channels.length > 1) _channelTabs(),
                Expanded(
                  child: _buildModeBody(),
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

  /// Тихий индикатор в шапке вместо snackbar: гаснет тапом по крестику.
  Widget _backgroundHintBar() {
    final colors = NoctwaveColors.of(context);
    return Container(
      width: double.infinity,
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Передача прервана: приложение сворачивалось. '
              'OLED-замок (🌙) держит экран активным.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: colors.textSecondary),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _showBackgroundHint = false),
          ),
        ],
      ),
    );
  }

  /// Меню устройства из шапки управления: переименовать, дублировать,
  /// удалить.
  void _showDeviceMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NoctwaveColors.of(context).surface,
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
                unawaited(_renameDevice());
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Дублировать'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_duplicateDevice());
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: NoctwavePalette.stop),
              title: const Text('Удалить устройство'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_deleteDevice());
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDevice() async {
    final store = widget.store;
    if (store == null) return;
    final controller = TextEditingController(text: widget.device.name);
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
    final devices = store.loadDevices();
    final idx = devices.indexWhere((d) => d.id == widget.device.id);
    if (idx < 0) return;
    final json = devices[idx].toJson()..['name'] = name;
    devices[idx] = DeviceProfile.fromJson(json);
    await store.saveDevices(devices);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Переименовано в «$name»')),
    );
  }

  Future<void> _duplicateDevice() async {
    final store = widget.store;
    if (store == null) return;
    final json = widget.device.toJson()
      ..['id'] = 'copy-${widget.device.id}-${DateTime.now().millisecondsSinceEpoch}'
      ..['name'] = '${widget.device.name} (копия)';
    final devices = store.loadDevices()..add(DeviceProfile.fromJson(json));
    await store.saveDevices(devices);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Копия создана')),
    );
  }

  Future<void> _deleteDevice() async {
    final store = widget.store;
    if (store == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Удалить «${widget.device.name}»?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NoctwavePalette.stop),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final devices =
        store.loadDevices().where((d) => d.id != widget.device.id).toList();
    await store.saveDevices(devices);
    if (!mounted) return;
    await _emergencyStop();
    if (mounted) Navigator.of(context).pop();
  }

  /// Рабочая область выбранного режима (ТЗ 3.2.3).
  Widget _buildModeBody() {
    final modeName = _modeIndex < _modes.length ? _modes[_modeIndex] : '';
    // Не-пульт режимы управляют всеми моторами сразу.
    void sendU(double u) => _sendToAll(u);

    switch (modeName) {
      case 'Пульт':
        return _remoteMode();
      case 'Жест':
        return GestureMode(
          device: widget.device,
          onCommand: (channelId, u) => _sendDynamic(channelId, u),
          onAll: (u) => _sendToAll(u),
          onSaveToRhythms: (samples) => unawaited(_saveGestureToRhythms(samples)),
        );
      case 'Ритмы':
        return widget.store == null
            ? _placeholderMode('Ритмы')
            : RhythmsMode(
                device: widget.device,
                store: widget.store!,
                onCommand: (channelId, cmdHex) =>
                    _sendPatternCommand(channelId, cmdHex),
              );
      case 'Автопилот':
        return AutopilotMode(onSample: sendU);
      case 'Сенсоры':
        return _accelerometerEvents == null
            ? _placeholderMode('Сенсоры (акселерометр недоступен)')
            : SensorsMode(
                onSample: sendU,
                accelerometerEvents: _accelerometerEvents!,
              );
      case 'Микрофон':
        return MicMode(onSample: sendU);
      case 'Медиа':
        return MediaMode(onSample: sendU);
      case 'Кегель':
        return KegelMode(onIntensity: sendU);
      default:
        return _placeholderMode(modeName);
    }
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
            if (_modes[i] == 'Сенсоры') unawaited(_ensureSensors());
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
        .skip(1) // индекс 0 — стоп, отдельная кнопка в доке
        .toList();
    final maxHex = channel.intensityStepsHex.last;
    // Активный режим именно этого канала: переключение канала не меняет
    // подсветку других и не сбрасывает их команды.
    final activeHex = _channelCommands[channel.id];
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.0,
      children: <Widget>[
        for (var i = 0; i < steps.length; i++)
          PulsingActive(
            intensity: activeHex == steps[i] ? (i + 1) / steps.length : 0,
            enabled: _settings.pulseAnimation,
            child: _ModeTile(
              label: 'Режим ${i + 1}',
              icon: _modeIcon(i + 1),
              active: activeHex == steps[i],
              intensity: (i + 1) / steps.length,
              onTap: () {
                _haptic(HapticFeedbackType.light);
                unawaited(_sendCommand(steps[i]));
              },
            ),
          ),
        // «Максимум» — последняя плитка сетки (не отдельная кнопка).
        // Тап = максимум; удержание = буст с возвратом при отпускании.
        PulsingActive(
          intensity: activeHex == maxHex ? 1 : 0,
          enabled: _settings.pulseAnimation,
          child: _ModeTile(
            label: 'Максимум',
            icon: Icons.bolt,
            active: activeHex == maxHex,
            intensity: 1,
            onTap: () {
              _haptic(HapticFeedbackType.light);
              unawaited(_sendCommand(maxHex));
            },
            onHoldStart: () => unawaited(_holdBoostStart()),
            onHoldEnd: () => unawaited(_holdBoostRelease()),
          ),
        ),
      ],
    );
  }

  /// Иконка режима по номеру (как в официальном приложении).
  IconData _modeIcon(int n) {
    switch (n) {
      case 1:
        return Icons.air;
      case 2:
        return Icons.filter_vintage;
      case 3:
        return Icons.waves;
      case 4:
        return Icons.swap_calls;
      case 5:
        return Icons.local_fire_department;
      case 6:
        return Icons.cyclone;
      case 7:
        return Icons.water_drop;
      case 8:
        return Icons.blur_circular;
      case 9:
        return Icons.grass;
      default:
        return Icons.toys_outlined;
    }
  }

  Widget _placeholderMode(String mode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.construction_outlined,
              size: 48, color: NoctwaveColors.of(context).textSecondary),
          const SizedBox(height: 12),
          Text('Режим «$mode» недоступен',
              style: TextStyle(color: NoctwaveColors.of(context).textSecondary)),
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

/// Плитка режима пульта: иконка + подпись, динамический акцент.
class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.icon,
    required this.active,
    required this.intensity,
    required this.onTap,
    this.onHoldStart,
    this.onHoldEnd,
  });

  final String label;
  final IconData icon;
  final bool active;
  final double intensity;
  final VoidCallback onTap;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  @override
  Widget build(BuildContext context) {
    // Акцент из темы (выбранный пользователем) → коралл по интенсивности.
    final base = Theme.of(context).colorScheme.primary;
    final accent = NoctwavePalette.accentForIntensity(intensity, from: base);
    final colors = NoctwaveColors.of(context);
    return GestureDetector(
      onLongPressStart: onHoldStart == null ? null : (_) => onHoldStart!(),
      onLongPressEnd: onHoldEnd == null ? null : (_) => onHoldEnd!(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? accent : colors.outline,
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
                  Icon(icon,
                      size: 30,
                      color: active ? accent : colors.textPrimary),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? accent : colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Типы тактильного отклика (ТЗ 3.1 Haptics).
enum HapticFeedbackType { light, medium, heavy }