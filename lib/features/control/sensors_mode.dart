import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/noctwave_theme.dart';

/// Режим «Сенсоры» — Shake (ТЗ 4.4): чтение акселерометра, расчёт модуля
/// ускорения за вычетом гравитации, экспоненциальное сглаживание (EMA),
/// настройка чувствительности (Gain) и плавности (alpha).
///
/// Математика фильтра вынесена в [ShakeFilter] для детерминированных
/// unit-тестов; источник данных — Stream ускорений (sensors_plus)
/// или ручная подача в тестах.
class ShakeFilter {
  ShakeFilter({
    this.alpha = 0.35,
    this.gain = 1.0,
    this.threshold = 0.15,
  });

  /// Коэффициент EMA (ТЗ 4.4): S_t = alpha * X_t + (1 - alpha) * S_(t-1).
  double alpha;

  /// Множитель чувствительности.
  double gain;

  /// Порог: ниже — u = 0 (СТОП), выше — линейный рост к 1.0.
  double threshold;

  double _smoothed = 0;
  double _gravity = 0;
  bool _gravityInitialised = false;
  double _lastMagnitude = 0;

  /// Текущее сглаженное значение 0..1 (нормализовано порогом и gain).
  double get level => _smoothed.clamp(0.0, 1.0);

  /// Подаёт вектор ускорения (м/с²) и возвращает u ∈ [0, 1].
  ///
  /// Гравитация вычитается высокочастотным фильтром: динамика —
  /// изменение модуля между соседними отсчётами (|Δ|), поэтому
  /// постоянная тряска не «растворяется» в медленной оценке гравитации.
  double push(double x, double y, double z) {
    final magnitude = math.sqrt(x * x + y * y + z * z);
    if (!_gravityInitialised) {
      _gravity = magnitude;
      _lastMagnitude = magnitude;
      _gravityInitialised = true;
      return 0; // первый отсчёт — только калибровка
    }
    // Медленная оценка гравитации (низкочастотный проход).
    _gravity = _gravity * 0.98 + magnitude * 0.02;
    // Высокочастотная динамика: скачок модуля между отсчётами.
    final delta = (magnitude - _lastMagnitude).abs();
    _lastMagnitude = magnitude;
    // Отклонение от гравитации, нормированное на 1g.
    final dynamic = (delta / 9.81 * gain).clamp(0.0, 2.0);
    // EMA сглаживание (ТЗ 4.4, alpha регулируется ползунком «Плавность»).
    _smoothed = alpha * dynamic + (1 - alpha) * _smoothed;
    // Noise gate: ниже порога → 0.
    if (_smoothed < threshold) return 0;
    return ((_smoothed - threshold) / (1 - threshold)).clamp(0.0, 1.0);
  }

  void reset() {
    _smoothed = 0;
    _gravityInitialised = false;
    _lastMagnitude = 0;
  }
}

class SensorsMode extends StatefulWidget {
  const SensorsMode({
    super.key,
    required this.onSample,
    required this.accelerometerEvents,
  });

  /// Колбэк нормализованного сигнала u(t) ∈ [0, 1].
  final void Function(double u) onSample;

  /// Поток событий акселерометра (x, y, z) в м/с².
  /// В продакшене — sensors_plus; в тестах — контролируемый Stream.
  final Stream<(double, double, double)> accelerometerEvents;

  @override
  State<SensorsMode> createState() => _SensorsModeState();
}

class _SensorsModeState extends State<SensorsMode> {
  final ShakeFilter _filter = ShakeFilter();
  StreamSubscription<(double, double, double)>? _sub;
  bool _active = false;
  bool _touchLock = false;
  double _currentLevel = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _sub?.cancel();
    _sub = widget.accelerometerEvents.listen((event) {
      final u = _filter.push(event.$1, event.$2, event.$3);
      _currentLevel = u;
      widget.onSample(u);
      if (mounted && !_touchLock) setState(() {});
    });
    setState(() => _active = true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.vibration, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Тряска (Shake)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Switch(
              value: _active,
              onChanged: (v) {
                setState(() => _active = v);
                if (v) {
                  _start();
                } else {
                  _sub?.cancel();
                  _sub = null;
                  _filter.reset();
                  widget.onSample(0);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Живой уровень.
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _currentLevel,
            minHeight: 12,
            backgroundColor: NoctwavePalette.outline,
            valueColor: AlwaysStoppedAnimation<Color>(
              NoctwavePalette.accentForIntensity(_currentLevel, from: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Плавность (alpha): ${_filter.alpha.toStringAsFixed(2)}',
            style: const TextStyle(color: NoctwavePalette.textSecondary)),
        Slider(
          value: _filter.alpha,
          min: 0.05,
          max: 1.0,
          onChanged: (v) => setState(() => _filter.alpha = v),
        ),
        Text('Чувствительность (Gain): ${_filter.gain.toStringAsFixed(2)}',
            style: const TextStyle(color: NoctwavePalette.textSecondary)),
        Slider(
          value: _filter.gain,
          min: 0.25,
          max: 3.0,
          onChanged: (v) => setState(() => _filter.gain = v),
        ),
        Text('Порог срабатывания: ${_filter.threshold.toStringAsFixed(2)}',
            style: const TextStyle(color: NoctwavePalette.textSecondary)),
        Slider(
          value: _filter.threshold,
          min: 0.0,
          max: 0.8,
          onChanged: (v) => setState(() => _filter.threshold = v),
        ),
        const SizedBox(height: 8),
        // Локальная блокировка касаний на время активной тряски (ТЗ 4.4).
        SwitchListTile(
          title: const Text('Блокировка касаний'),
          subtitle: const Text('Не реагировать на экран во время тряски'),
          value: _touchLock,
          onChanged: (v) => setState(() => _touchLock = v),
        ),
      ],
    );
  }
}
