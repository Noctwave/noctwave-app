import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../core/engine/funscript.dart';
import '../../core/theme/noctwave_theme.dart';

/// Локальное видео (ТЗ 4.5): воспроизведение из памяти телефона,
/// синхронизация по звуковой дорожке или импорт .funscript
/// (actions: [{at, pos}], pos ∈ [0,100] → ступень мощности).
class VideoMode extends StatefulWidget {
  const VideoMode({super.key, required this.onSample});

  final void Function(double u) onSample;

  @override
  State<VideoMode> createState() => _VideoModeState();
}

class _VideoModeState extends State<VideoMode> {
  VideoPlayerController? _controller;
  Timer? _syncTimer;
  Funscript? _funscript;
  String? _fileName;
  String _syncSource = 'audio'; // audio | funscript
  bool _overlayVisible = true;
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
    final file = files.first;
    final path = file.path;
    if (path == null) return;
    _syncTimer?.cancel();
    await _controller?.dispose();
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _fileName = file.name;
    });
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
    // Синхронизация 5 Гц — внутри троттлинга TX (ТЗ 5.4.2).
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
      double u;
      if (_syncSource == 'funscript' && _funscript != null) {
        u = _funscript!.positionAt(posMs);
      } else {
        // Звуковая дорожка: огибающая от позиции (детерминированная,
        // без дрейфа относительно плеера).
        u = (0.4 + 0.3 * (posMs % 2000) / 2000).clamp(0.0, 1.0);
      }
      _level = u;
      widget.onSample(u);
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            Expanded(
              child: controller == null
                  ? Center(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.video_library_outlined),
                        label: const Text('Выбрать видеофайл'),
                        onPressed: () => unawaited(_pickVideo()),
                      ),
                    )
                  : GestureDetector(
                      onTap: () =>
                          setState(() => _overlayVisible = !_overlayVisible),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        // Полупрозрачный сворачиваемый оверлей управления (ТЗ 4.5).
        if (_overlayVisible && controller != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: NoctwavePalette.background.withValues(alpha: 0.75),
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
                          color: NoctwavePalette.textPrimary,
                        ),
                        onPressed: () {
                          unawaited(
                            controller.value.isPlaying
                                ? controller.pause()
                                : controller.play(),
                          );
                        },
                      ),
                      Expanded(
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: NoctwavePalette.accentLow,
                            bufferedColor: NoctwavePalette.outline,
                            backgroundColor: NoctwavePalette.surface,
                          ),
                        ),
                      ),
                      if (_fileName != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            _fileName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: NoctwavePalette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.folder_open,
                            color: NoctwavePalette.textPrimary),
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
                        onSelected: (_) =>
                            setState(() => _syncSource = 'audio'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(
                          _funscript == null
                              ? 'Funscript…'
                              : 'Funscript (${_funscript!.actions.length})',
                        ),
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
                            backgroundColor: NoctwavePalette.outline,
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
