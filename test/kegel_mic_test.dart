import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/engine/kegel_timer.dart';
import 'package:noctwave_app/core/engine/mic_analyser.dart';

void main() {
  group('KegelTimer — интервальный таймер (ТЗ 4.5)', () {
    test('проходит фазы Сжатие → Удержание → Отдых и завершается', () async {
      final timer = KegelTimer(tickMs: 50);
      final phases = <KegelPhase>[];
      final sub = timer.events.listen((e) => phases.add(e.phase));
      timer.start(const KegelSettings(
        squeezeMs: 100,
        holdMs: 100,
        restMs: 100,
        repeats: 2,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await sub.cancel();
      timer.dispose();
      expect(phases.first, KegelPhase.squeeze);
      expect(phases, contains(KegelPhase.hold));
      expect(phases, contains(KegelPhase.rest));
      expect(phases.last, KegelPhase.done);
      expect(timer.completedCycles, 2);
    });

    test('stop обрывает таймер', () async {
      final timer = KegelTimer(tickMs: 50);
      var events = 0;
      final sub = timer.events.listen((_) => events++);
      timer.start(const KegelSettings(squeezeMs: 500, repeats: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      timer.stop();
      final countAfterStop = events;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();
      timer.dispose();
      expect(events, countAfterStop);
      expect(timer.isRunning, isFalse);
    });
  });

  group('MicAnalyser — RMS, Noise Gate, AGC (ТЗ 4.4)', () {
    test('тишина ниже порога даёт 0 (СТОП)', () {
      final analyser = MicAnalyser(gateThresholdDb: -45);
      // Тихий сигнал ~-60 дБ.
      final u = analyser.push(List<double>.filled(1024, 0.001));
      expect(u, 0.0);
    });

    test('громкий сигнал выше порога даёт u > 0', () {
      final analyser = MicAnalyser(gateThresholdDb: -45);
      // Синус амплитудой 0.5 → RMS ~0.35 → ~-9 дБ.
      final samples = List<double>.generate(
        1024,
        (i) => 0.5 * math.sin(i * 0.05),
      );
      final u = analyser.push(samples);
      expect(u, greaterThan(0.5));
    });

    test('AGC нормализует под громкость окружения', () {
      final analyser = MicAnalyser(gateThresholdDb: -60, agcEnabled: true);
      // Сначала тихое окружение — калибровка дна.
      analyser.push(List<double>.filled(1024, 0.002));
      // Потом громкий сигнал на фоне тихого дна → близко к 1.0.
      final loud = List<double>.generate(1024, (i) => 0.4 * math.sin(i * 0.05));
      final u = analyser.push(loud);
      expect(u, greaterThan(0.6));
    });

    test('reset очищает окно и оценки', () {
      final analyser = MicAnalyser();
      analyser.push(List<double>.generate(512, (i) => 0.5 * math.sin(i * 0.05)));
      analyser.reset();
      expect(analyser.push(List<double>.filled(1024, 0.001)), 0.0);
    });
  });
}
