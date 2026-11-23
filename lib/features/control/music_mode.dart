import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/engine/pcm_decoder.dart';
import '../../core/theme/noctwave_theme.dart';

/// Локальная музыка (ТЗ 4.4): выбор MP3/M4A/WAV/FLAC, мини-плеер
/// и маппинг энергии низких частот (40–150 Гц) на ступени интенсивности.
///
/// На iOS PCM декодируется нативно (AVAudioFile) и анализируется
/// [FftAnalyser] по позиции плеера — без дрейфа. На платформах без
/// нативного декодера — синтетическая огибающая-заглушка.
class MusicMode extends StatefulWidget {
  const MusicMode({super.key, required this.onSample});

  final void Function(double u) onSample;

  @override
  State<MusicMode> createState() => _MusicModeState();
}

class _MusicModeState extends State<MusicMode> {
  final AudioPlayer _player = AudioPlayer();
  final MusicAnalyser _analyser = MusicAnalyser();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  String? _filePath;
  String? _fileName;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.positionStream.listen((p) {
      _position = p;
      if (_playing) {
        unawaited(_analyseAt(p.inMilliseconds));
      }
    });
    _stateSub = _player.playerStateStream.listen((s) {
      final playing = s.playing;
      if (!playing && _playing) {
        widget.onSample(0);
        _level = 0;
      }
      if (mounted) setState(() => _playing = playing);
    });
  }

  /// Реальный FFT низких частот по позиции плеера (iOS, ТЗ 4.4).
  /// Если PCM-декодер недоступен — синтетическая огибающая-заглушка.
  Future<void> _analyseAt(int positionMs) async {
    double level;
    if (_analyser.isReady) {
      level = await _analyser.levelAt(positionMs);
    } else {
      final t = positionMs / 1000.0;
      level = (0.5 +
              0.3 * math.sin(t * 2 * math.pi * 0.5) +
              0.2 * math.sin(t * 2 * math.pi * 2.0))
          .clamp(0.0, 1.0);
    }
    if (!mounted || !_playing) return;
    _level = level;
    widget.onSample(_level);
    setState(() {});
  }

  @override
  void dispose() {
    unawaited(_positionSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_analyser.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['mp3', 'm4a', 'wav', 'flac'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final path = file.path;
    if (path == null) return;
    final duration = await _player.setFilePath(path);
    // Декодируем PCM для реального FFT (iOS). Не блокирует плеер.
    unawaited(_analyser.load(path));
    if (!mounted) return;
    setState(() {
      _filePath = path;
      _fileName = file.name;
      _duration = duration ?? Duration.zero;
    });
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        OutlinedButton.icon(
          icon: const Icon(Icons.audio_file_outlined),
          label: Text(_fileName ?? 'Выбрать аудиофайл (MP3/M4A/WAV/FLAC)'),
          onPressed: () => unawaited(_pickFile()),
        ),
        const SizedBox(height: 16),
        if (_filePath != null) ...<Widget>[
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
          const SizedBox(height: 12),
          Slider(
            value: _duration.inMilliseconds == 0
                ? 0
                : (_position.inMilliseconds / _duration.inMilliseconds)
                    .clamp(0.0, 1.0),
            onChanged: (v) {
              unawaited(_player.seek(
                Duration(
                  milliseconds: (v * _duration.inMilliseconds).round(),
                ),
              ));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(_fmt(_position),
                  style: const TextStyle(color: NoctwavePalette.textSecondary)),
              Text(_fmt(_duration),
                  style: const TextStyle(color: NoctwavePalette.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton.outlined(
                icon: const Icon(Icons.replay_10),
                onPressed: () => unawaited(_player.seek(
                  _position - const Duration(seconds: 10),
                )),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                label: Text(_playing ? 'Пауза' : 'Играть'),
                onPressed: () =>
                    unawaited(_playing ? _player.pause() : _player.play()),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                icon: const Icon(Icons.forward_10),
                onPressed: () => unawaited(_player.seek(
                  _position + const Duration(seconds: 10),
                )),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _analyser.isReady
                ? 'Анализ низких частот 40–150 Гц по PCM трека (FFT).'
                : 'Синтетическая огибающая: нативный PCM-декодер доступен на iOS.',
            style: TextStyle(
              color: NoctwaveColors.of(context).textSecondary,
              fontSize: 12,
            ),
          ),
        ] else
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Файл не выбран',
                style: TextStyle(color: NoctwavePalette.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}
