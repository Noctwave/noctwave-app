import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:record/record.dart';

import '../../core/engine/mic_analyser.dart';
import '../../core/theme/noctwave_theme.dart';

/// Режим «Микрофон» (ТЗ 4.4): захват PCM локально (без записи на диск
/// и без сети), скользящий RMS в дБ, Noise Gate и AGC.
/// Разрешение RECORD_AUDIO запрашивается строго при первом входе.
class MicMode extends StatefulWidget {
  const MicMode({super.key, required this.onSample});

  final void Function(double u) onSample;

  @override
  State<MicMode> createState() => _MicModeState();
}

class _MicModeState extends State<MicMode> {
  final AudioRecorder _recorder = AudioRecorder();
  final MicAnalyser _analyser = MicAnalyser(gateThresholdDb: -45);
  StreamSubscription<Uint8List>? _sub;

  bool _active = false;
  bool _permissionDenied = false;
  double _level = 0;

  @override
  void dispose() {
    unawaited(_stop());
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    // Разрешение — строго по факту входа в режим (ТЗ 7.3).
    final granted = await _recorder.hasPermission();
    if (!granted) {
      if (mounted) setState(() => _permissionDenied = true);
      return;
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      ),
    );
    _sub = stream.listen((bytes) {
      // PCM16 little-endian → нормализованные float -1..1.
      final samples = <double>[];
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        samples.add(data.getInt16(i, Endian.little) / 32768.0);
      }
      final u = _analyser.push(samples);
      _level = u;
      widget.onSample(u);
      if (mounted) setState(() {});
    });
    if (mounted) {
      setState(() {
        _active = true;
        _permissionDenied = false;
      });
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // Уже остановлен.
    }
    _analyser.reset();
    widget.onSample(0);
    if (mounted) setState(() => _active = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (_permissionDenied)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Доступ к микрофону запрещён. Разрешите его в настройках '
                'системы — остальные режимы работают без него.',
                style: TextStyle(color: NoctwavePalette.stop),
              ),
            ),
          ),
        Row(
          children: <Widget>[
            const Icon(Icons.mic, color: NoctwavePalette.accentLow),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Микрофон (Ambient Sound)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Switch(
              value: _active,
              onChanged: (v) => unawaited(v ? _start() : _stop()),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _level,
            minHeight: 12,
            backgroundColor: NoctwavePalette.outline,
            valueColor: AlwaysStoppedAnimation<Color>(
              NoctwavePalette.accentForIntensity(_level),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Noise Gate: ${_analyser.gateThresholdDb.round()} дБ',
            style: const TextStyle(color: NoctwavePalette.textSecondary)),
        Slider(
          value: _analyser.gateThresholdDb,
          min: -80,
          max: -20,
          onChanged: (v) => setState(() => _analyser.gateThresholdDb = v),
        ),
        SwitchListTile(
          title: const Text('AGC (автонормализация)'),
          subtitle: const Text('Подстройка под громкость окружения'),
          value: _analyser.agcEnabled,
          onChanged: (v) => setState(() => _analyser.agcEnabled = v),
        ),
        const SizedBox(height: 8),
        const Text(
          'Аудио обрабатывается только в оперативной памяти: '
          'без записи на диск и без отправки в сеть.',
          style: TextStyle(
            color: NoctwavePalette.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
