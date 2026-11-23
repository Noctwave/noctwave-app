import 'dart:async';

import '../models/device_profile.dart';

/// Запись и воспроизведение сессий (ТЗ 4.3): поток событий
/// `(timestampMs, channelId, cmdHex)` с точностью до 50 мс.
class PatternRecorder {
  PatternRecorder();

  final List<PatternEvent> _events = <PatternEvent>[];
  Stopwatch? _stopwatch;

  bool get isRecording => _stopwatch?.isRunning ?? false;

  int get elapsedMs => _stopwatch?.elapsedMilliseconds ?? 0;

  void start() {
    _events.clear();
    _stopwatch = Stopwatch()..start();
  }

  /// Регистрирует отправленную команду; время — от старта записи.
  void record(String channelId, String cmdHex) {
    final sw = _stopwatch;
    if (sw == null || !sw.isRunning) return;
    _events.add(PatternEvent(
      atMs: sw.elapsedMilliseconds,
      channelId: channelId,
      cmdHex: cmdHex,
    ));
  }

  /// Останавливает запись, подрезает пустоту в начале/конце (ТЗ 4.3)
  /// и возвращает готовый паттерн.
  RecordedPattern finish({required String id, required String name, required String deviceId}) {
    _stopwatch?.stop();
    _stopwatch = null;
    final trimmed = _trimSilence(_events);
    final duration = trimmed.isEmpty ? 0 : trimmed.last.atMs;
    return RecordedPattern(
      id: id,
      name: name,
      deviceId: deviceId,
      durationMs: duration,
      events: trimmed,
    );
  }

  void cancel() {
    _stopwatch?.stop();
    _stopwatch = null;
    _events.clear();
  }

  /// Подрезка пустоты: убираем сдвиг от первого события и повторяющиеся
  /// события с одним и тем же cmdHex подряд (квант 50 мс — ТЗ 4.3).
  static List<PatternEvent> _trimSilence(List<PatternEvent> events) {
    if (events.isEmpty) return <PatternEvent>[];
    final offset = events.first.atMs;
    final result = <PatternEvent>[];
    String? lastCmd;
    String? lastChannel;
    for (final e in events) {
      if (e.cmdHex == lastCmd && e.channelId == lastChannel) {
        // Повтор той же команды ближе 50 мс — отбрасываем (дедуп).
        if (result.isNotEmpty && e.atMs - result.last.atMs < 50) continue;
      }
      result.add(PatternEvent(
        atMs: e.atMs - offset,
        channelId: e.channelId,
        cmdHex: e.cmdHex,
      ));
      lastCmd = e.cmdHex;
      lastChannel = e.channelId;
    }
    return result;
  }
}

/// Воспроизведение ритма (ТЗ 4.3): запуск, пауза, Loop, скорость 0.5x–2.0x.
class PatternPlayer {
  PatternPlayer({required this.onCommand});

  /// Колбэк отправки: (channelId, cmdHex) в момент воспроизведения.
  final void Function(String channelId, String cmdHex) onCommand;

  Timer? _timer;
  int _index = 0;
  int _loopCount = 0;
  RecordedPattern? _pattern;
  double _speed = 1.0;
  bool _loop = true;
  int _lastTickMs = 0;

  bool get isPlaying => _timer?.isActive ?? false;

  int get currentLoop => _loopCount;

  void play(RecordedPattern pattern, {double speed = 1.0, bool loop = true}) {
    stop();
    _pattern = pattern;
    _speed = speed;
    _loop = loop;
    _index = 0;
    _loopCount = 0;
    _lastTickMs = 0;
    if (pattern.events.isEmpty) return;
    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) => _tick());
  }

  void _tick() {
    final pattern = _pattern;
    if (pattern == null) return;
    final virtualNow = _lastTickMs + 25 * _speed;
    _lastTickMs = virtualNow.toInt();
    final events = pattern.events;
    while (_index < events.length && events[_index].atMs <= _lastTickMs) {
      final e = events[_index];
      onCommand(e.channelId, e.cmdHex);
      _index++;
    }
    if (_index >= events.length) {
      if (_loop) {
        _loopCount++;
        _index = 0;
        _lastTickMs = 0;
      } else {
        stop();
      }
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _index = 0;
    _pattern = null;
  }
}

/// Состояние записанной сессии для UI (индикатор REC).
class RecordingState {
  const RecordingState({this.isRecording = false, this.elapsedMs = 0});

  final bool isRecording;
  final int elapsedMs;
}
