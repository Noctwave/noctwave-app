import 'dart:async';

/// Фаза интервального таймера Кегеля (ТЗ 4.5):
/// Сжатие → Удержание → Отдых × N повторов.
enum KegelPhase { squeeze, hold, rest, done }

class KegelPhaseEvent {
  const KegelPhaseEvent(this.phase, this.remainingMs);

  final KegelPhase phase;
  final int remainingMs;
}

/// Настройки таймера Кегеля.
class KegelSettings {
  const KegelSettings({
    this.squeezeMs = 5000,
    this.holdMs = 3000,
    this.restMs = 5000,
    this.repeats = 10,
  });

  final int squeezeMs;
  final int holdMs;
  final int restMs;
  final int repeats;
}

/// Интервальный таймер Кегеля (ТЗ 4.5).
///
/// Логика отделена от Flutter: поток событий фаз, подписчик отправляет
/// мягкие команды на устройство в фазах сжатия/удержания и СТОП в отдыхе.
class KegelTimer {
  KegelTimer({this.tickMs = 250});

  final int tickMs;

  Timer? _timer;
  KegelSettings _settings = const KegelSettings();
  int _elapsedInPhaseMs = 0;
  int _completedCycles = 0;
  final StreamController<KegelPhaseEvent> _controller =
      StreamController<KegelPhaseEvent>.broadcast();

  Stream<KegelPhaseEvent> get events => _controller.stream;

  KegelPhase get currentPhase => _phase;
  KegelPhase _phase = KegelPhase.done;

  int get completedCycles => _completedCycles;

  bool get isRunning => _timer?.isActive ?? false;

  void start(KegelSettings settings) {
    stop();
    _settings = settings;
    _phase = KegelPhase.squeeze;
    _elapsedInPhaseMs = 0;
    _completedCycles = 0;
    _emit();
    _timer = Timer.periodic(Duration(milliseconds: tickMs), (_) => _tick());
  }

  void _tick() {
    _elapsedInPhaseMs += tickMs;
    final phaseDuration = switch (_phase) {
      KegelPhase.squeeze => _settings.squeezeMs,
      KegelPhase.hold => _settings.holdMs,
      KegelPhase.rest => _settings.restMs,
      KegelPhase.done => 0,
    };
    if (_elapsedInPhaseMs >= phaseDuration) {
      _elapsedInPhaseMs = 0;
      switch (_phase) {
        case KegelPhase.squeeze:
          _phase = KegelPhase.hold;
        case KegelPhase.hold:
          _phase = KegelPhase.rest;
        case KegelPhase.rest:
          _completedCycles++;
          if (_completedCycles >= _settings.repeats) {
            _phase = KegelPhase.done;
            _timer?.cancel();
            _timer = null;
            _elapsedInPhaseMs = 0;
            _emit();
            return;
          }
          _phase = KegelPhase.squeeze;
        case KegelPhase.done:
          break;
      }
    }
    _emit();
  }

  void _emit() {
    final phaseDuration = switch (_phase) {
      KegelPhase.squeeze => _settings.squeezeMs,
      KegelPhase.hold => _settings.holdMs,
      KegelPhase.rest => _settings.restMs,
      KegelPhase.done => 0,
    };
    _controller.add(
      KegelPhaseEvent(_phase, (phaseDuration - _elapsedInPhaseMs).clamp(0, 1 << 30)),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _phase = KegelPhase.done;
    _elapsedInPhaseMs = 0;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
