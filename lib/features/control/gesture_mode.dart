import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/models/device_profile.dart';
import '../../core/theme/noctwave_theme.dart';

/// Режим «Жест» (ТЗ 4.2): 1D-кривая для одноканальных и 2D XY-пэд для
/// двухканальных устройств, зацикливание (Loop) с множителем скорости.
class GestureMode extends StatefulWidget {
  const GestureMode({
    super.key,
    required this.device,
    required this.onCommand,
    this.onSaveToRhythms,
  });

  final DeviceProfile device;

  /// Колбэк отправки команды: (channelId | null, u | (u1, u2)).
  /// Для 1D — один канал и уровень 0..1; для 2D — пара уровней.
  final void Function(String channelId, double u) onCommand;

  /// Сохранить зафиксированный зацикленный жест в «Ритмы» (ТЗ 4.2).
  final void Function(List<GestureSample> samples)? onSaveToRhythms;

  @override
  State<GestureMode> createState() => _GestureModeState();
}

/// Одна точка жеста: момент (мс) и уровни каналов.
class GestureSample {
  GestureSample(this.tMs, this.u1, this.u2);

  final int tMs;
  final double u1;
  final double u2;
}

class _GestureModeState extends State<GestureMode> {
  final List<GestureSample> _track = <GestureSample>[];
  final GlobalKey<_GestureCanvasState> _canvasKey = GlobalKey<_GestureCanvasState>();

  bool _looping = false;
  double _speed = 1.0;
  Timer? _loopTimer;
  int _loopPos = 0;
  final Stopwatch _loopClock = Stopwatch();

  bool get _is2D => widget.device.channels.length >= 2;

  @override
  void dispose() {
    _loopTimer?.cancel();
    super.dispose();
  }

  void _onSample(double u1, double u2) {
    final channels = widget.device.channels;
    final tMs = _track.isEmpty ? 0 : _track.last.tMs + 16;
    _track.add(GestureSample(tMs, u1, u2));
    if (_track.length > 3000) _track.removeAt(0); // ~50 с записи
    if (channels.isEmpty) return;
    if (_is2D) {
      widget.onCommand(channels[0].id, u1.clamp(0.0, 1.0));
      widget.onCommand(channels[1].id, u2.clamp(0.0, 1.0));
    } else {
      widget.onCommand(channels[0].id, u1.clamp(0.0, 1.0));
    }
    _canvasKey.currentState?._repaint();
  }

  void _toggleLoop() {
    if (_track.length < 2) return;
    setState(() => _looping = !_looping);
    if (_looping) {
      _startLoop();
    } else {
      _loopTimer?.cancel();
      _loopTimer = null;
    }
  }

  void _startLoop() {
    _loopTimer?.cancel();
    _loopPos = 0;
    _loopClock..reset()..start();
    const tickMs = 25;
    _loopTimer = Timer.periodic(const Duration(milliseconds: tickMs), (_) {
      if (_track.isEmpty) return;
      final virtualMs = _loopClock.elapsedMilliseconds * _speed;
      final total = _track.last.tMs == 0 ? 1 : _track.last.tMs;
      final pos = virtualMs % total;
      // Ближайшая точка трека.
      var idx = (pos / total * (_track.length - 1)).round();
      idx = idx.clamp(0, _track.length - 1);
      if (idx != _loopPos || virtualMs % total < tickMs * _speed) {
        _loopPos = idx;
        final s = _track[idx];
        final channels = widget.device.channels;
        if (channels.isNotEmpty) {
          widget.onCommand(channels[0].id, s.u1);
          if (_is2D && channels.length > 1) {
            widget.onCommand(channels[1].id, s.u2);
          }
        }
      }
      _canvasKey.currentState?._repaint();
    });
  }

  void _saveToRhythms() {
    widget.onSaveToRhythms?.call(List<GestureSample>.of(_track));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _GestureCanvas(
              key: _canvasKey,
              is2D: _is2D,
              track: _track,
              onSample: _onSample,
              loopProgress: _looping && _track.length > 1 ? _loopPos / (_track.length - 1) : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _looping ? NoctwavePalette.accentHigh : NoctwavePalette.accentLow,
                  ),
                  icon: Icon(_looping ? Icons.stop_circle_outlined : Icons.loop),
                  label: Text(_looping ? 'Стоп Loop' : 'Loop'),
                  onPressed: _track.length < 2 ? null : _toggleLoop,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<double>(
                value: _speed,
                items: const <DropdownMenuItem<double>>[
                  DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                  DropdownMenuItem(value: 1.0, child: Text('1.0x')),
                  DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                  DropdownMenuItem(value: 2.0, child: Text('2.0x')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _speed = v);
                  if (_looping) _startLoop();
                },
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Сохранить жест в «Ритмы»',
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: _track.length < 2 ? null : _saveToRhythms,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Полотно рисования: 1D — вертикальная ось, 2D — XY-пэд.
class _GestureCanvas extends StatefulWidget {
  const _GestureCanvas({
    super.key,
    required this.is2D,
    required this.track,
    required this.onSample,
    this.loopProgress,
  });

  final bool is2D;
  final List<GestureSample> track;
  final void Function(double u1, double u2) onSample;
  final double? loopProgress;

  @override
  State<_GestureCanvas> createState() => _GestureCanvasState();
}

class _GestureCanvasState extends State<_GestureCanvas> {
  void _repaint() {
    if (mounted) setState(() {});
  }

  void _handlePan(DragUpdateDetails details, BoxConstraints constraints) {
    final u2 = 1.0 - (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
    final u1 = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
    widget.onSample(widget.is2D ? u1 : u2, u2);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final custom = CustomPaint(
          size: Size.infinite,
          painter: _TrackPainter(
            is2D: widget.is2D,
            track: widget.track,
            loopProgress: widget.loopProgress,
          ),
        );
        return GestureDetector(
          onPanUpdate: (d) => _handlePan(d, constraints),
          onPanEnd: (_) {},
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: NoctwavePalette.surface,
                border: Border.all(color: NoctwavePalette.outline),
                borderRadius: BorderRadius.circular(16),
              ),
              child: custom,
            ),
          ),
        );
      },
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.is2D, required this.track, this.loopProgress});

  final bool is2D;
  final List<GestureSample> track;
  final double? loopProgress;

  @override
  void paint(Canvas canvas, Size size) {
    // Сетка.
    final grid = Paint()
      ..color = NoctwavePalette.outline.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(size.width * i / 4, 0),
        Offset(size.width * i / 4, size.height),
        grid,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    if (track.isEmpty) return;
    final total = track.last.tMs == 0 ? 1 : track.last.tMs;

    final paint = Paint()
      ..color = NoctwavePalette.accentLow
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    for (var i = 0; i < track.length; i++) {
      final s = track[i];
      final Offset p;
      if (is2D) {
        p = Offset(s.u1 * size.width, (1 - s.u2) * size.height);
      } else {
        p = Offset(s.tMs / total * size.width, (1 - s.u1) * size.height);
      }
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);

    // Позиция воспроизведения Loop.
    final progress = loopProgress;
    if (progress != null) {
      final x = is2D
          ? null
          : progress * size.width;
      final p = is2D
          ? track[(progress * (track.length - 1)).round()]
          : null;
      final Offset cursor;
      if (is2D && p != null) {
        cursor = Offset(p.u1 * size.width, (1 - p.u2) * size.height);
      } else {
        cursor = Offset(x ?? 0, 0);
      }
      canvas.drawCircle(
        cursor,
        7,
        Paint()..color = NoctwavePalette.accentHigh.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrackPainter oldDelegate) => true;
}
