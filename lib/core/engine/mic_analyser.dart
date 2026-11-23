import 'dart:math' as math;

/// Анализатор уровня звука для режима «Микрофон» (ТЗ 4.4):
/// скользящий RMS в дБ, Noise Gate и AGC (автонормализация).
///
/// Чистый Dart без зависимостей: PCM-поток подаётся снаружи
/// (нативный захват на устройстве, тестовые данные в unit-тестах).
class MicAnalyser {
  MicAnalyser({
    this.gateThresholdDb = -45.0,
    this.agcEnabled = false,
    this.windowSize = 1024,
  });

  /// Порог Noise Gate, дБ: сигналы ниже маппятся в 0 (СТОП).
  double gateThresholdDb;

  /// AGC: подстройка под общую громкость окружения (ТЗ 4.4).
  bool agcEnabled;

  /// Размер скользящего окна RMS.
  final int windowSize;

  final List<double> _window = <double>[];
  double _peakDb = -120;
  double _noiseFloorDb = -120;

  /// Подаёт PCM-отсчёты (нормализованные float -1..1 или int16)
  /// и возвращает нормализованный уровень u ∈ [0, 1].
  double push(List<num> samples) {
    _window.addAll(samples.map((s) => s.toDouble()));
    if (_window.length > windowSize) {
      _window.removeRange(0, _window.length - windowSize);
    }
    if (_window.isEmpty) return 0;

    // RMS → дБ (эталон 1.0 = 0 dBFS).
    var sumSquares = 0.0;
    for (final s in _window) {
      sumSquares += s * s;
    }
    final rms = math.sqrt(sumSquares / _window.length);
    final db = rms <= 0 ? -120.0 : 20 * math.log(rms) / math.ln10;

    // Обновление пика и шумового дна (медленные оценки).
    if (db > _peakDb) {
      _peakDb = db;
    } else {
      _peakDb = _peakDb * 0.995 + db * 0.005; // медленный спад пика
    }
    if (db < _noiseFloorDb || _noiseFloorDb == -120) {
      _noiseFloorDb = db;
    } else {
      _noiseFloorDb = _noiseFloorDb * 0.995 + db * 0.005; // медленный рост дна
    }

    // Noise Gate.
    if (db < gateThresholdDb) return 0;

    if (agcEnabled) {
      // Нормализация в диапазон [noiseFloor, peak].
      final range = (_peakDb - _noiseFloorDb).clamp(6.0, 120.0);
      final normalized = ((db - _noiseFloorDb) / range).clamp(0.0, 1.0);
      return normalized;
    }
    // Без AGC: фиксированный диапазон -60..0 дБ.
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }

  void reset() {
    _window.clear();
    _peakDb = -120;
    _noiseFloorDb = -120;
  }
}
