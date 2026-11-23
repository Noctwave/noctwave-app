import 'dart:math' as math;
import 'dart:typed_data';

/// FFT-анализатор для локальной музыки (ТЗ 4.4): выделение
/// низкочастотного диапазона 40–150 Гц и огибающей амплитуды.
///
/// Реализация Cooley-Tukey radix-2 на чистом Dart — без нативных
/// зависимостей, детерминированная и покрытая unit-тестами.
class FftAnalyser {
  FftAnalyser({
    this.sampleRate = 44100,
    this.fftSize = 1024,
    this.lowHz = 40,
    this.highHz = 150,
  }) : assert(_isPowerOfTwo(fftSize), 'fftSize должен быть степенью двойки');

  final int sampleRate;
  final int fftSize;
  final double lowHz;
  final double highHz;

  static bool _isPowerOfTwo(int n) => n > 0 && (n & (n - 1)) == 0;

  /// Вычисляет нормализованную энергию низкочастотного диапазона
  /// для PCM-окна и возвращает u ∈ [0, 1].
  ///
  /// Энергия нормируется относительно полной энергии окна, чтобы
  /// уровень не зависел от общей громкости трека (эквивалент AGC).
  double lowBandEnergy(List<double> samples) {
    if (samples.length < fftSize) return 0;
    final window = samples.sublist(samples.length - fftSize);

    // Окно Ханна: подавление спектральной утечки.
    final real = Float64List(fftSize);
    final imag = Float64List(fftSize);
    for (var i = 0; i < fftSize; i++) {
      final hann = 0.5 * (1 - math.cos(2 * math.pi * i / (fftSize - 1)));
      real[i] = window[i] * hann;
    }

    _fft(real, imag);

    // Индексы бинов диапазона lowHz..highHz.
    final binHz = sampleRate / fftSize;
    final lowBin = math.max(1, (lowHz / binHz).floor());
    final highBin = math.min(fftSize ~/ 2 - 1, (highHz / binHz).ceil());

    var bandEnergy = 0.0;
    var totalEnergy = 0.0;
    for (var k = 1; k < fftSize ~/ 2; k++) {
      final power = real[k] * real[k] + imag[k] * imag[k];
      totalEnergy += power;
      if (k >= lowBin && k <= highBin) bandEnergy += power;
    }
    if (totalEnergy <= 0) return 0;
    // Доля энергии низкого диапазона: чистый бас → близко к 1.
    return (bandEnergy / totalEnergy).clamp(0.0, 1.0);
  }

  /// In-place radix-2 FFT (Cooley-Tukey).
  static void _fft(Float64List real, Float64List imag) {
    final n = real.length;
    // Bit-reversal permutation.
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        var tmp = real[i];
        real[i] = real[j];
        real[j] = tmp;
        tmp = imag[i];
        imag[i] = imag[j];
        imag[j] = tmp;
      }
    }
    // Бабочки.
    for (var len = 2; len <= n; len <<= 1) {
      final angle = -2 * math.pi / len;
      final wReal = math.cos(angle);
      final wImag = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var curReal = 1.0;
        var curImag = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final uReal = real[i + k];
          final uImag = imag[i + k];
          final vReal = real[i + k + len ~/ 2] * curReal -
              imag[i + k + len ~/ 2] * curImag;
          final vImag = real[i + k + len ~/ 2] * curImag +
              imag[i + k + len ~/ 2] * curReal;
          real[i + k] = uReal + vReal;
          imag[i + k] = uImag + vImag;
          real[i + k + len ~/ 2] = uReal - vReal;
          imag[i + k + len ~/ 2] = uImag - vImag;
          final nextReal = curReal * wReal - curImag * wImag;
          curImag = curReal * wImag + curImag * wReal;
          curReal = nextReal;
        }
      }
    }
  }
}
