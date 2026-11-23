import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/engine/autopilot.dart';
import 'package:noctwave_app/core/engine/pattern_engine.dart';
import 'package:noctwave_app/core/models/device_profile.dart';

void main() {
  group('Autopilot — формы генератора (ТЗ 4.3)', () {
    test('wave: сигнал в диапазоне min..max', () {
      final shape = WaveShape();
      for (var t = 0; t < 5000; t += 100) {
        final u = shape.sample(t, min: 0.2, max: 0.8, tempo: 0.5);
        expect(u, greaterThanOrEqualTo(0.2));
        expect(u, lessThanOrEqualTo(0.8));
      }
    });

    test('pulse: чередует max и min половинами периода', () {
      final shape = PulseShape();
      // tempo=1 → период 1000 мс: [0,500) — max, [500,1000) — min.
      expect(shape.sample(0, min: 0.0, max: 1.0, tempo: 1.0), 1.0);
      expect(shape.sample(400, min: 0.0, max: 1.0, tempo: 1.0), 1.0);
      expect(shape.sample(500, min: 0.0, max: 1.0, tempo: 1.0), 0.0);
      expect(shape.sample(900, min: 0.0, max: 1.0, tempo: 1.0), 0.0);
      // Следующий цикл.
      expect(shape.sample(1000, min: 0.0, max: 1.0, tempo: 1.0), 1.0);
    });

    test('pulse: масштаб в диапазон min..max', () {
      final shape = PulseShape();
      expect(shape.sample(0, min: 0.25, max: 0.75, tempo: 1.0), 0.75);
      expect(shape.sample(600, min: 0.25, max: 0.75, tempo: 1.0), 0.25);
    });

    test('ramp: растёт от min к max внутри цикла', () {
      final shape = RampShape();
      final start = shape.sample(0, min: 0.0, max: 1.0, tempo: 1.0);
      final middle = shape.sample(500, min: 0.0, max: 1.0, tempo: 1.0);
      expect(start, lessThan(middle));
      expect(middle, closeTo(0.5, 0.01));
    });

    test('chaos: детерминирован при одинаковом seed', () {
      final a = ChaosShape(seed: 7);
      final b = ChaosShape(seed: 7);
      for (var t = 0; t < 3000; t += 400) {
        expect(
          a.sample(t, min: 0.0, max: 1.0, tempo: 1.0),
          b.sample(t, min: 0.0, max: 1.0, tempo: 1.0),
        );
      }
    });

    test('shapeByName возвращает нужную форму', () {
      expect(shapeByName('wave'), isA<WaveShape>());
      expect(shapeByName('pulse'), isA<PulseShape>());
      expect(shapeByName('ramp'), isA<RampShape>());
      expect(shapeByName('chaos'), isA<ChaosShape>());
      expect(shapeByName('unknown'), isA<WaveShape>());
    });
  });

  group('PatternRecorder — запись сессий (ТЗ 4.3)', () {
    test('запись и подрезка пустоты в начале', () async {
      final recorder = PatternRecorder();
      recorder.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      recorder.record('ch1', 'F41D7C');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      recorder.record('ch1', 'F7864E');
      final pattern = recorder.finish(
        id: 'r1', name: 'Тест', deviceId: 'd1',
      );
      expect(pattern.events.length, 2);
      // Первое событие обрезано к нулю.
      expect(pattern.events.first.atMs, 0);
      expect(pattern.events[1].atMs, greaterThan(0));
      expect(pattern.durationMs, pattern.events.last.atMs);
    });

    test('finish без записи даёт пустой паттерн', () {
      final recorder = PatternRecorder();
      final pattern = recorder.finish(id: 'r', name: 'n', deviceId: 'd');
      expect(pattern.events, isEmpty);
      expect(pattern.durationMs, 0);
    });

    test('cancel сбрасывает запись', () {
      final recorder = PatternRecorder();
      recorder.start();
      recorder.record('ch1', 'F41D7C');
      recorder.cancel();
      expect(recorder.isRecording, isFalse);
      final pattern = recorder.finish(id: 'r', name: 'n', deviceId: 'd');
      expect(pattern.events, isEmpty);
    });
  });

  group('PatternPlayer — воспроизведение (ТЗ 4.3)', () {
    test('воспроизводит события по таймингам и зацикливается', () async {
      final commands = <String>[];
      final player = PatternPlayer(
        onCommand: (channel, cmd) => commands.add(cmd),
      );
      const pattern = RecordedPattern(
        id: 'r1',
        name: 'Тест',
        deviceId: 'd1',
        durationMs: 100,
        events: <PatternEvent>[
          PatternEvent(atMs: 0, channelId: 'ch1', cmdHex: 'F41D7C'),
          PatternEvent(atMs: 50, channelId: 'ch1', cmdHex: 'F7864E'),
        ],
      );
      player.play(pattern, loop: true);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      player.stop();
      // Минимум один полный проход + начало второго.
      expect(commands, contains('F41D7C'));
      expect(commands, contains('F7864E'));
      expect(commands.length, greaterThanOrEqualTo(3));
    });

    test('stop останавливает воспроизведение', () async {
      final commands = <String>[];
      final player = PatternPlayer(
        onCommand: (channel, cmd) => commands.add(cmd),
      );
      const pattern = RecordedPattern(
        id: 'r1',
        name: 'Тест',
        deviceId: 'd1',
        durationMs: 1000,
        events: <PatternEvent>[
          PatternEvent(atMs: 500, channelId: 'ch1', cmdHex: 'F41D7C'),
        ],
      );
      player.play(pattern, loop: false);
      player.stop();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(commands, isEmpty);
      expect(player.isPlaying, isFalse);
    });
  });
}
