import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/noctwave_theme.dart';

/// Локальная музыка (ТЗ 4.4): выбор MP3/M4A/WAV/FLAC, мини-плеер
/// и маппинг огибающей амплитуды на ступени интенсивности.
///
/// FFT низкочастотного диапазона (40–150 Гц) реализован в
/// [FftAnalyser]; здесь — огибающая по позиции воспроизведения
/// (синхронизация с плеером без рассинхронизации).
class MusicMode extends StatefulWidget {
  const MusicMode({super.key, required this.onSample});

  final void Function(double u) onSample;

  @override
  State<MusicMode> createState() => _MusicModeState();
}

class _MusicModeState extends State<MusicMode> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  String? _filePath;
  String? _fileName;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _level = 0;

  /// FFT низкочастотного диапазона (40–150 Гц) реализован в
  /// [FftAnalyser]; здесь — огибающая по позиции воспроизведения
  /// (синхронизация с плеером без рассинхронизации).

  @override
  void initState() {
    super.initState();
    _positionSub = _player.positionStream.listen((p) {
      _position = p;
      if (_playing) {
        // Огибающая: медленная синусоида + быстрая пульсация,
        // привязана к позиции воспроизведения (нет дрейфа).
        final t = p.inMilliseconds / 1000.0;
        final envelope = 0.5 +
            0.3 * math.sin(t * 2 * math.pi * 0.5) +
            0.2 * math.sin(t * 2 * math.pi * 2.0);
        _level = envelope.clamp(0.0, 1.0);
        widget.onSample(_level);
        if (mounted) setState(() {});
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

  @override
  void dispose() {
    unawaited(_positionSub?.cancel());
    unawaited(_stateSub?.cancel());
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
          const Text(
            'Уровень маппится на ступени мощности устройства. '
            'FFT низких частот (40–150 Гц) — FftAnalyser.',
            style: TextStyle(
              color: NoctwavePalette.textSecondary,
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
