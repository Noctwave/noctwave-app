import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/ble/ble_advertiser.dart';
import '../../core/ble/tx_scheduler.dart';
import '../../core/models/device_profile.dart';
import '../../core/theme/noctwave_theme.dart';
import 'oled_lock_overlay.dart';

/// Экран управления устройством (ТЗ 3.2.3): переключатель режимов,
/// рабочая область (MVP — «Пульт»), OLED-замок и нижний док.
class ControlPage extends StatefulWidget {
  const ControlPage({
    super.key,
    required this.device,
    BleAdvertiserGateway? gateway,
  }) : _injectedGateway = gateway;

  final DeviceProfile device;
  final BleAdvertiserGateway? _injectedGateway;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  late final BleAdvertiserGateway _gateway =
      widget._injectedGateway ?? MethodChannelBleAdvertiser();

  late final TxScheduler _scheduler = TxScheduler(gateway: _gateway);

  int _modeIndex = 0;
  int _channelIndex = 0;
  bool _txActive = false;
  bool _oledLock = false;
  String? _lastCommandHex;
  DateTime? _sessionStart;
  Timer? _sessionTicker;

  static const _modes = <String>['Пульт', 'Жест', 'Ритмы', 'Сенсоры'];

  DeviceChannel? get _channel {
    final channels = widget.device.channels;
    if (channels.isEmpty) return null;
    return channels[_channelIndex.clamp(0, channels.length - 1)];
  }

  @override
  void dispose() {
    _sessionTicker?.cancel();
    unawaited(_scheduler.dispose());
    super.dispose();
  }

  void _haptic(HapticFeedbackType type) {
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
                  child: _modeIndex == 0
                      ? _remoteMode()
                      : _placeholderMode(_modes[_modeIndex]),
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
                backgroundColor: NoctwavePalette.surface,
                side: const BorderSide(color: NoctwavePalette.outline),
              ),
              icon: const Icon(Icons.fiber_manual_record,
                  color: NoctwavePalette.stop, size: 16),
              label: const Text('REC'),
              onPressed: () {},
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
