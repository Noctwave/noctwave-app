import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/engine/fft_analyser.dart';
import 'package:noctwave_app/core/engine/funscript.dart';

void main() {
  group('FftAnalyser — низкочастотный диапазон 40–150 Гц (ТЗ 4.4)', () {
    List<double> sine(double freq, int n, int rate) => List<double>.generate(
          n,
          (i) => math.sin(2 * math.pi * freq * i / rate),
        );

    test('чистый бас 80 Гц → энергия диапазона близка к 1', () {
      final fft = FftAnalyser(sampleRate: 44100, fftSize: 1024);
      final u = fft.lowBandEnergy(sine(80, 1024, 44100));
      expect(u, greaterThan(0.7));
    });

    test('высокий тон 5000 Гц → энергия диапазона близка к 0', () {
      final fft = FftAnalyser(sampleRate: 44100, fftSize: 1024);
      final u = fft.lowBandEnergy(sine(5000, 1024, 44100));
      expect(u, lessThan(0.1));
    });

    test('тишина даёт 0', () {
      final fft = FftAnalyser();
      expect(fft.lowBandEnergy(List<double>.filled(1024, 0)), 0.0);
    });

    test('короткое окно (< fftSize) даёт 0', () {
      final fft = FftAnalyser();
      expect(fft.lowBandEnergy(sine(80, 100, 44100)), 0.0);
    });

    test('бас + высокий тон: доля баса между 0 и 1', () {
      final fft = FftAnalyser(sampleRate: 44100, fftSize: 1024);
      final mixed = List<double>.generate(
        1024,
        (i) =>
            math.sin(2 * math.pi * 80 * i / 44100) +
            math.sin(2 * math.pi * 5000 * i / 44100),
      );
      final u = fft.lowBandEnergy(mixed);
      expect(u, greaterThan(0.1));
      expect(u, lessThan(0.9));
    });
  });

  group('Funscript — импорт .funscript (ТЗ 4.5)', () {
    const source = '''
    {
      "version": "1.0",
      "actions": [
        {"at": 0, "pos": 0},
        {"at": 1000, "pos": 50},
        {"at": 2000, "pos": 100},
        {"at": 3000, "pos": 0}
      ]
    }
    ''';

    test('парсит actions и сортирует по времени', () {
      final script = Funscript.parse(source);
      expect(script.actions.length, 4);
      expect(script.durationMs, 3000);
    });

    test('positionAt: точные ключевые точки', () {
      final script = Funscript.parse(source);
      expect(script.positionAt(0), 0.0);
      expect(script.positionAt(1000), 0.5);
      expect(script.positionAt(2000), 1.0);
      expect(script.positionAt(3000), 0.0);
    });

    test('positionAt: линейная интерполяция между точками', () {
      final script = Funscript.parse(source);
      expect(script.positionAt(500), closeTo(0.25, 0.001));
      expect(script.positionAt(1500), closeTo(0.75, 0.001));
    });

    test('positionAt: за пределами диапазона — крайние значения', () {
      final script = Funscript.parse(source);
      expect(script.positionAt(-100), 0.0);
      expect(script.positionAt(9999), 0.0);
    });

    test('пустой funscript даёт 0', () {
      final script = Funscript.parse('{"actions": []}');
      expect(script.positionAt(500), 0.0);
      expect(script.durationMs, 0);
    });

    test('pos клампится в [0, 100]', () {
      final script = Funscript.parse(
        '{"actions": [{"at": 0, "pos": 150}, {"at": 100, "pos": -20}]}',
      );
      expect(script.positionAt(0), 1.0);
      expect(script.positionAt(100), 0.0);
    });
  });
}
