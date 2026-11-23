import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/features/control/sensors_mode.dart';

void main() {
  group('ShakeFilter — EMA-сглаживание (ТЗ 4.4)', () {
    test('первый отсчёт калибрует гравитацию и даёт 0', () {
      final f = ShakeFilter(alpha: 0.5, gain: 1.0, threshold: 0.0);
      expect(f.push(0, 0, 9.81), 0.0);
    });

    test('S_t = alpha * X_t + (1 - alpha) * S_(t-1)', () {
      final f = ShakeFilter(alpha: 0.5, gain: 1.0, threshold: 0.0);
      f.push(0, 0, 9.81);
      // Рывок +1g между отсчётами: dynamic ≈ 1.0.
      final u1 = f.push(0, 0, 19.62);
      // EMA первого скачка: 0.5 * 1.0 = ~0.5, не мгновенный 1.0.
      expect(u1, greaterThan(0.3));
      expect(u1, lessThan(0.9));
    });

    test('лежащий телефон (только гравитация) даёт 0', () {
      final f = ShakeFilter(alpha: 0.35, gain: 1.0, threshold: 0.15);
      f.push(0, 0, 9.81);
      for (var i = 0; i < 200; i++) {
        expect(f.push(0.02, -0.01, 9.81), 0.0);
      }
    });

    test('тряска (переменный модуль) даёт u > 0 и растёт с амплитудой', () {
      double shakeLevel(double amplitude) {
        final f = ShakeFilter(alpha: 0.5, gain: 1.0, threshold: 0.05);
        f.push(0, 0, 9.81);
        var u = 0.0;
        // Чередование модуля ±amplitude вокруг гравитации — имитация тряски.
        for (var i = 0; i < 100; i++) {
          final z = 9.81 + (i.isEven ? amplitude : -amplitude);
          u = f.push(0, 0, z);
        }
        return u;
      }

      final weak = shakeLevel(0.5);
      final strong = shakeLevel(5.0);
      expect(weak, greaterThan(0));
      expect(strong, greaterThan(weak));
      expect(strong, greaterThan(0.5));
    });

    test('малая alpha сильнее сглаживает', () {
      final smooth = ShakeFilter(alpha: 0.1, gain: 1.0, threshold: 0.0);
      final sharp = ShakeFilter(alpha: 0.9, gain: 1.0, threshold: 0.0);
      smooth.push(0, 0, 9.81);
      sharp.push(0, 0, 9.81);
      final smoothU = smooth.push(0, 0, 20);
      final sharpU = sharp.push(0, 0, 20);
      expect(sharpU, greaterThan(smoothU));
    });

    test('reset возвращает фильтр в исходное состояние', () {
      final f = ShakeFilter(alpha: 0.5, gain: 1.0, threshold: 0.1);
      f.push(0, 0, 9.81);
      f.push(0, 0, 30);
      f.reset();
      expect(f.level, 0.0);
      expect(f.push(0, 0, 9.81), 0.0);
    });

    test('диагональная тряска по трём осям тоже считается', () {
      final f = ShakeFilter(alpha: 0.5, gain: 1.0, threshold: 0.05);
      f.push(0, 0, 9.81);
      var u = 0.0;
      for (var i = 0; i < 50; i++) {
        final sign = i.isEven ? 1.0 : -1.0;
        u = f.push(3 * sign, 3 * sign, 9.81 + 3 * sign);
      }
      expect(u, greaterThan(0));
      expect(u, lessThanOrEqualTo(1.0));
      // sanity: модуль диагонального рывка > одноосевого
      expect(math.sqrt(27), greaterThan(3));
    });
  });
}
