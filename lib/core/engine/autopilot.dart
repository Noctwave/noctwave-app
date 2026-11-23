import 'dart:math' as math;

/// Процедурный генератор «Автопилот» (ТЗ 4.3): Wave / Chaos.
///
/// Генерирует нормализованный сигнал `u(t) ∈ [0, 1]`, который затем
/// квантуется [TxScheduler.quantize] в команды устройства.
/// Без таймеров и состояния — чистая функция от времени, удобно тестировать.
abstract class AutopilotShape {
  /// Возвращает u(t) для момента [tMs] при диапазоне мощности [min]..[max]
  /// и темпе [tempo] (циклов в секунду).
  double sample(int tMs, {required double min, required double max, required double tempo});

  /// Нормирует базовый сигнал 0..1 в диапазон min..max.
  double map(double unit, double min, double max) =>
      min + (max - min) * unit.clamp(0.0, 1.0);
}

/// Плавная синусоидальная волна (ТЗ 4.3 «Плавная волна»).
class WaveShape extends AutopilotShape {
  @override
  double sample(int tMs, {required double min, required double max, required double tempo}) {
    final phase = (tMs / 1000.0) * tempo * 2 * math.pi;
    final unit = (math.sin(phase) + 1) / 2; // 0..1
    return map(unit, min, max);
  }
}

/// Пульсация: прямоугольная волна с плавными фронтами.
class PulseShape extends AutopilotShape {
  @override
  double sample(int tMs, {required double min, required double max, required double tempo}) {
    final periodMs = (1000.0 / tempo).round();
    final inPeriod = tMs % periodMs;
    final unit = inPeriod < periodMs / 2 ? 1.0 : 0.0;
    return map(unit, min, max);
  }
}

/// Нарастание / Edging: линейный рост от min к max за цикл, затем сброс.
class RampShape extends AutopilotShape {
  @override
  double sample(int tMs, {required double min, required double max, required double tempo}) {
    final periodMs = (1000.0 / tempo).round();
    final unit = (tMs % periodMs) / periodMs;
    return map(unit, min, max);
  }
}

/// Случайный хаос (ТЗ 4.3 «Случайный хаос»): детерминированный псевдослучай,
/// обновляется с шагом [stepMs] — значение стабильно внутри шага.
class ChaosShape extends AutopilotShape {
  ChaosShape({this.stepMs = 400, int seed = 42}) : _random = math.Random(seed);

  final int stepMs;
  final math.Random _random;
  int _lastStep = -1;
  double _lastValue = 0;

  @override
  double sample(int tMs, {required double min, required double max, required double tempo}) {
    final step = tMs ~/ stepMs;
    if (step != _lastStep) {
      _lastStep = step;
      _lastValue = _random.nextDouble();
    }
    return map(_lastValue, min, max);
  }
}

/// Фабрика форм автопилота по идентификатору из UI.
AutopilotShape shapeByName(String name) {
  switch (name) {
    case 'pulse':
      return PulseShape();
    case 'ramp':
      return RampShape();
    case 'chaos':
      return ChaosShape();
    case 'wave':
    default:
      return WaveShape();
  }
}
