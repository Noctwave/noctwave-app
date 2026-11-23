import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/engine/kegel_timer.dart';
import '../../core/theme/noctwave_theme.dart';

/// Опциональный модуль «Таймер Кегеля» (ТЗ 4.5): Сжатие → Удержание →
/// Отдых × N. В фазах сжатия/удержания подаются мягкие команды
/// (40% мощности), в отдыхе — СТОП.
class KegelMode extends StatefulWidget {
  const KegelMode({super.key, required this.onIntensity});

  /// Колбэк уровня интенсивности: u = 0.4 в сжатии/удержании, 0 в отдыхе.
  final void Function(double u) onIntensity;

  @override
  State<KegelMode> createState() => _KegelModeState();
}

class _KegelModeState extends State<KegelMode> {
  final KegelTimer _timer = KegelTimer();
  StreamSubscription<KegelPhaseEvent>? _sub;

  KegelSettings _settings = const KegelSettings();
  KegelPhase _phase = KegelPhase.done;
  int _remainingMs = 0;

  @override
  void initState() {
    super.initState();
    _sub = _timer.events.listen((e) {
      if (!mounted) return;
      setState(() {
        _phase = e.phase;
        _remainingMs = e.remainingMs;
      });
      // Мягкие команды: сжатие и удержание — 40%, отдых/конец — СТОП.
      widget.onIntensity(
        e.phase == KegelPhase.squeeze || e.phase == KegelPhase.hold
            ? 0.4
            : 0.0,
      );
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _timer.dispose();
    super.dispose();
  }

  void _start() => _timer.start(_settings);

  @override
  Widget build(BuildContext context) {
    final running = _timer.isRunning;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: <Widget>[
                Text(
                  _phaseLabel(_phase),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: _phaseColor(_phase),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  _remainingMs > 0
                      ? '${(_remainingMs / 1000).toStringAsFixed(1)} с'
                      : '—',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w200,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Повторов: ${_timer.completedCycles} / ${_settings.repeats}',
                  style: const TextStyle(color: NoctwavePalette.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _settingRow(
          'Сжатие: ${(_settings.squeezeMs / 1000).toStringAsFixed(0)} с',
          _settings.squeezeMs / 1000,
          1,
          15,
          (v) => _settings =
              _settings.copyWith(squeezeMs: (v * 1000).round()),
        ),
        _settingRow(
          'Удержание: ${(_settings.holdMs / 1000).toStringAsFixed(0)} с',
          _settings.holdMs / 1000,
          1,
          15,
          (v) => _settings = _settings.copyWith(holdMs: (v * 1000).round()),
        ),
        _settingRow(
          'Отдых: ${(_settings.restMs / 1000).toStringAsFixed(0)} с',
          _settings.restMs / 1000,
          1,
          30,
          (v) => _settings = _settings.copyWith(restMs: (v * 1000).round()),
        ),
        _settingRow(
          'Повторы: ${_settings.repeats}',
          _settings.repeats.toDouble(),
          1,
          50,
          (v) => _settings =
              _settings.copyWith(repeats: v.round()),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: running
                      ? NoctwavePalette.accentHigh
                      : Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: Icon(running ? Icons.stop : Icons.play_arrow),
                label: Text(running ? 'Остановить' : 'Начать тренировку'),
                onPressed: () {
                  if (running) {
                    _timer.stop();
                    widget.onIntensity(0);
                    setState(() => _phase = KegelPhase.done);
                  } else {
                    _start();
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _settingRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(color: NoctwavePalette.textSecondary)),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ],
      );

  String _phaseLabel(KegelPhase phase) => switch (phase) {
        KegelPhase.squeeze => 'Сжатие',
        KegelPhase.hold => 'Удержание',
        KegelPhase.rest => 'Отдых',
        KegelPhase.done => 'Готово',
      };

  Color _phaseColor(KegelPhase phase) => switch (phase) {
        KegelPhase.squeeze => NoctwavePalette.accentLow,
        KegelPhase.hold => NoctwavePalette.accentHigh,
        KegelPhase.rest => NoctwavePalette.textSecondary,
        KegelPhase.done => NoctwavePalette.textSecondary,
      };
}

extension on KegelSettings {
  KegelSettings copyWith({
    int? squeezeMs,
    int? holdMs,
    int? restMs,
    int? repeats,
  }) =>
      KegelSettings(
        squeezeMs: squeezeMs ?? this.squeezeMs,
        holdMs: holdMs ?? this.holdMs,
        restMs: restMs ?? this.restMs,
        repeats: repeats ?? this.repeats,
      );
}
