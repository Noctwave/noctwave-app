import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'fft_analyser.dart';

/// Мост к нативному PCM-декодеру (iOS: AVAudioFile).
///
/// Декодирует локальный аудиофайл в PCM и отдаёт окна для FFT-анализа
/// по позиции плеера — без дрейфа и рассинхронизации (ТЗ 4.4).
/// На платформах без нативного модуля [available] = false.
class PcmDecoder {
  PcmDecoder({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.pulselocal/pcm_decoder');

  final MethodChannel _channel;

  bool _loaded = false;
  double _sampleRate = 44100;

  bool get isLoaded => _loaded;
  double get sampleRate => _sampleRate;

  /// Декодирует файл. Возвращает true при успехе.
  Future<bool> load(String path) async {
    if (!Platform.isIOS) return false;
    try {
      final info = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'load',
        <String, Object>{'path': path},
      );
      if (info == null) return false;
      _sampleRate = (info['sampleRate'] as num?)?.toDouble() ?? 44100;
      _loaded = true;
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Окно PCM, заканчивающееся на позиции [positionMs].
  Future<List<double>> windowAt(int positionMs, {int fftSize = 1024}) async {
    if (!_loaded) return <double>[];
    try {
      final window = await _channel.invokeMethod<List<dynamic>>(
        'windowAt',
        <String, Object>{'positionMs': positionMs, 'fftSize': fftSize},
      );
      return window?.map((e) => (e as num).toDouble()).toList() ?? <double>[];
    } on PlatformException {
      return <double>[];
    }
  }

  Future<void> unload() async {
    _loaded = false;
    try {
      await _channel.invokeMethod<void>('unload');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }
}

/// Анализатор музыки: соединяет PCM-декодер и FFT (ТЗ 4.4).
/// Возвращает нормализованную энергию низких частот 40–150 Гц
/// для позиции воспроизведения.
class MusicAnalyser {
  MusicAnalyser({PcmDecoder? decoder})
      : _decoder = decoder ?? PcmDecoder();

  final PcmDecoder _decoder;
  FftAnalyser? _fft;

  bool get isReady => _decoder.isLoaded && _fft != null;

  Future<bool> load(String path) async {
    final ok = await _decoder.load(path);
    if (!ok) {
      _fft = null;
      return false;
    }
    _fft = FftAnalyser(
      sampleRate: _decoder.sampleRate.round(),
      fftSize: 1024,
    );
    return true;
  }

  /// Энергия низкого диапазона для позиции плеера, u ∈ [0, 1].
  Future<double> levelAt(int positionMs) async {
    final fft = _fft;
    if (fft == null) return 0;
    final window = await _decoder.windowAt(positionMs, fftSize: fft.fftSize);
    if (window.isEmpty) return 0;
    return fft.lowBandEnergy(window);
  }

  Future<void> dispose() => _decoder.unload();
}
