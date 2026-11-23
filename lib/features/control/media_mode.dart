import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../core/engine/funscript.dart';
import '../../core/engine/pcm_decoder.dart';
import '../../core/theme/noctwave_theme.dart';

/// Режим «Медиа» — объединённые Музыка и Видео (ТЗ 4.4 / 4.5).
///
/// Суть одна: локальный файл (аудио или видео) управляет устройством
/// через анализ звука. Для видео доступен также .funscript.
/// Переключатель Аудио/Видео в шапке режима.
class MediaMode extends StatefulWidget {
  const MediaMode({super.key, required this.onSample});

  final void Function(double u) onSample;

  @override
  State<MediaMode> createState() => _MediaModeState();
}

class _MediaModeState extends State<MediaMode> {
  bool _isVideo = false;

  @override
  Widget build(BuildContext context) {
    final colors = NoctwaveColors.of(context);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment(
                value: false,
                label: Text('Аудио'),
                icon: Icon(Icons.music_note),
              ),
              ButtonSegment(
                value: true,
                label: Text('Видео'),
                icon: Icon(Icons.videocam_outlined),
              ),
            ],
            selected: <bool>{_isVideo},
            onSelectionChanged: (s) {
              // СТОП при переключении: старый источник больше не управляет.
              widget.onSample(0);
              setState(() => _isVideo = s.first);
            },
          ),
        ),
        Expanded(
          child: _isVideo
              ? _VideoPanel(onSample: widget.onSample, colors: colors)
              : _AudioPanel(onSample: widget.onSample, colors: colors),
        ),
      ],
    );
  }
}

// ── Аудио ─────────────────────────────────────────────────────────────

class _AudioPanel extends StatefulWidget {
  const _AudioPanel({required this.onSample, required this.colors});

  final void Function(double u) onSample;
  final NoctwaveColors colors;

  @override
  State<_AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<_AudioPanel> {
  final AudioPlayer _player = AudioPlayer();
  final MusicAnalyser _analyser = MusicAnalyser();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

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
      if (_playing) unawaited(_analyseAt(p.inMilliseconds));
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

  Future<void> _analyseAt(int positionMs) async {
    double level;
    if (_analyser.isReady) {
      level = await _analyser.levelAt(positionMs);
    } else {
      final t = positionMs / 1000.0;
      level = (0.5 + 0.3 * (t % 2) / 2).clamp(0.0, 1.0);
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
    final path = files.first.path;
    if (path == null) return;
    final duration = await _player.setFilePath(path);
    unawaited(_analyser.load(path));
    if (!mounted) return;
    setState(() {
      _fileName = files.first.name;
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
    final colors = widget.colors;
    if (_fileName == null) {
      return Center(
        child: OutlinedButton.icon(
          icon: const Icon(Icons.audio_file_outlined),
          label: const Text('Выбрать аудио (MP3/M4A/WAV/FLAC)'),
          onPressed: () => unawaited(_pickFile()),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(_fileName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _level,
            minHeight: 12,
            backgroundColor: colors.outline,
            valueColor: AlwaysStoppedAnimation<Color>(
              NoctwavePalette.accentForIntensity(_level),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Slider(
          value: _duration.inMilliseconds == 0
              ? 0
              : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0),
          onChanged: (v) => unawaited(_player.seek(
            Duration(milliseconds: (v * _duration.inMilliseconds).round()),
          )),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(_fmt(_position), style: TextStyle(color: colors.textSecondary)),
            Text(_fmt(_duration), style: TextStyle(color: colors.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton.outlined(
              icon: const Icon(Icons.replay_10),
              onPressed: () => unawaited(
                  _player.seek(_position - const Duration(seconds: 10))),
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
              onPressed: () => unawaited(
                  _player.seek(_position + const Duration(seconds: 10))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _analyser.isReady
              ? 'Анализ низких частот 40–150 Гц по PCM трека (FFT).'
              : 'Синтетическая огибающая: нативный PCM-декодер доступен на iOS.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.folder_open),
          label: const Text('Другой файл'),
          onPressed: () => unawaited(_pickFile()),
        ),
      ],
    );
  }
}

// ── Видео ─────────────────────────────────────────────────────────────

class _VideoPanel extends StatefulWidget {
  const _VideoPanel({required this.onSample, required this.colors});

  final void Function(double u) onSample;
  final NoctwaveColors colors;

  @override
  State<_VideoPanel> createState() => _VideoPanelState();
}

class _VideoPanelState extends State<_VideoPanel> {
  VideoPlayerController? _controller;
  Timer? _syncTimer;
  Funscript? _funscript;
  String _syncSource = 'audio';
  double _level = 0;

  @override
  void dispose() {
    _syncTimer?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final files = await FilePicker.pickFiles(type: FileType.video);
    if (files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    _syncTimer?.cancel();
    await _controller?.dispose();
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    _startSync();
  }

  Future<void> _pickFunscript() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['funscript'],
    );
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    try {
      final script = Funscript.parse(String.fromCharCodes(bytes));
      if (!mounted) return;
      setState(() {
        _funscript = script;
        _syncSource = 'funscript';
      });
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Некорректный .funscript')),
      );
    }
  }

  void _startSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final controller = _controller;
      if (controller == null || !controller.value.isPlaying) {
        if (_level != 0) {
          _level = 0;
          widget.onSample(0);
        }
        return;
      }
      final posMs = controller.value.position.inMilliseconds;
      final u = _syncSource == 'funscript' && _funscript != null
          ? _funscript!.positionAt(posMs)
          : (0.4 + 0.3 * (posMs % 2000) / 2000).clamp(0.0, 1.0);
      _level = u;
      widget.onSample(u);
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final controller = _controller;
    if (controller == null) {
      return Center(
        child: OutlinedButton.icon(
          icon: const Icon(Icons.video_library_outlined),
          label: const Text('Выбрать видеофайл'),
          onPressed: () => unawaited(_pickVideo()),
        ),
      );
    }
    return Stack(
      children: <Widget>[
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: colors.background.withValues(alpha: 0.75),
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: colors.textPrimary,
                      ),
                      onPressed: () => unawaited(
                        controller.value.isPlaying
                            ? controller.pause()
                            : controller.play(),
                      ),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: Theme.of(context).colorScheme.primary,
                          bufferedColor: colors.outline,
                          backgroundColor: colors.surface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.folder_open, color: colors.textPrimary),
                      tooltip: 'Другой файл',
                      onPressed: () => unawaited(_pickVideo()),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('Звук видео'),
                      selected: _syncSource == 'audio',
                      onSelected: (_) => setState(() => _syncSource = 'audio'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(_funscript == null
                          ? 'Funscript…'
                          : 'Funscript (${_funscript!.actions.length})'),
                      selected: _syncSource == 'funscript',
                      onSelected: (_) {
                        if (_funscript == null) {
                          unawaited(_pickFunscript());
                        } else {
                          setState(() => _syncSource = 'funscript');
                        }
                      },
                    ),
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 60,
                        child: LinearProgressIndicator(
                          value: _level,
                          minHeight: 8,
                          backgroundColor: colors.outline,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            NoctwavePalette.accentForIntensity(_level),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
