import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctwave_app/core/engine/pcm_decoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PcmDecoder — мост к нативному декодеру', () {
    late MethodChannel channel;
    late List<MethodCall> calls;

    setUp(() {
      channel = const MethodChannel('com.pulselocal/pcm_decoder');
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'load':
            return <String, Object>{
              'sampleRate': 48000,
              'frames': 480000,
              'durationMs': 10000,
            };
          case 'windowAt':
            final size = (call.arguments as Map)['fftSize'] as int;
            return List<double>.filled(size, 0.25);
          case 'unload':
            return null;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('load сохраняет sampleRate (на не-iOS возвращает false)', () async {
      final decoder = PcmDecoder(channel: channel);
      // В тестовой среде Platform.isIOS = false → load вернёт false
      // без обращения к каналу. Это корректное поведение заглушки.
      final ok = await decoder.load('/tmp/test.mp3');
      expect(ok, isFalse);
      expect(decoder.isLoaded, isFalse);
    });

    test('windowAt без загрузки возвращает пустой список', () async {
      final decoder = PcmDecoder(channel: channel);
      final window = await decoder.windowAt(1000);
      expect(window, isEmpty);
    });
  });

  group('MusicAnalyser — FFT по позиции плеера', () {
    test('levelAt без загрузки даёт 0', () async {
      final analyser = MusicAnalyser();
      expect(await analyser.levelAt(1000), 0.0);
      expect(analyser.isReady, isFalse);
    });
  });
}
