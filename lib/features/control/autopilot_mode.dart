import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/engine/autopilot.dart';
import '../../core/theme/noctwave_theme.dart';

/// Режим «Автопилот» (ТЗ 4.3): процедурный генератор Wave/Pulse/Ramp/Chaos.
/// Пользователь выбирает форму, диапазон мощности (min..max) и темп;
/// движок генерирует u(t) и квантует в команды через колбэк.
class AutopilotMode extends StatefulWidget {
  const AutopilotMode({super.key, required this.onSample});

  /// Колбэк: нормализованный сигнал u(t) ∈ [0, 1] (уже с диапазоном).
  final void Function(double u) onSample;

  @override
  State<AutopilotMode> createState() => _AutopilotModeState();
}

class _AutopilotModeState extends State<AutopilotMode> {
  String _shape = 'wave';
  double _min = 0.1;
  double _max = 0.8;
  double _tempo = 0.5; // циклов в секунду

  bool _running = false;
  Timer? _timer;
  int _tMs = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _running = !_running);
    if (_running) {
      _tMs = 0;
      _timer?.cancel();
      // 5 Гц — внутри допустимого диапазона троттлинга (ТЗ 5.4.2).
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        _tMs += 200;
        final shape = shapeByName(_shape);
        widget.onSample(shape.sample(_tMs, min: _min, max: _max, tempo: _tempo));
        if (mounted) setState(() {});
      });
    } else {
      _timer?.cancel();
      _timer = null;
      widget.onSample(0); // СТОП
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _shapeChips(),
        const SizedBox(height: 16),
        _rangeSlider(),
        const SizedBox(height: 8),
        _tempoSlider(),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor:
                  _running ? NoctwavePalette.accentHigh : NoctwavePalette.accentLow,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Остановить автопилот' : 'Запустить автопилот'),
            onPressed: _toggle,
          ),
        ),
      ],
    );
  }

  Widget _shapeChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _shapeChip('wave', 'Плавная волна'),
        _shapeChip('pulse', 'Пульсация'),
        _shapeChip('ramp', 'Нарастание'),
        _shapeChip('chaos', 'Хаос'),
      ],
    );
  }

  Widget _shapeChip(String id, String label) => ChoiceChip(
        label: Text(label),
        selected: _shape == id,
        onSelected: (_) => setState(() => _shape = id),
      );

  Widget _rangeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Диапазон мощности: ${(_min * 100).round()}% – ${(_max * 100).round()}%',
            style: const TextStyle(color: NoctwavePalette.textSecondary)),
        RangeSlider(
          values: RangeValues(_min, _max),
          min: 0,
          max: 1,
          onChanged: (v) => setState(() {
            _min = v.start;
            _max = v.end;
          }),
        ),
      ],
    );
  }

  Widget _tempoSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Темп: ${_tempo.toStringAsFixed(2)} цикл/с',
            style: const TextStyle(color: NoctwavePalette.textSecondary)),
        Slider(
          value: _tempo,
          min: 0.1,
          max: 3.0,
          onChanged: (v) => setState(() => _tempo = v),
        ),
      ],
    );
  }
}
