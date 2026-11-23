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
    this.onAll,
    this.onSaveToRhythms,
  });

  final DeviceProfile device;

  /// Колбэк команды конкретного канала (2D XY-пэд).
  final void Function(String channelId, double u) onCommand;

  /// Колбэк «все моторы сразу» (1D-кривая): уровень 0..1 на все каналы.
  final void Function(double u)? onAll;

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
  /// Скользящее окно для отрисовки (~8 с).
  final List<GestureSample> _track = <GestureSample>[];

  /// Полный трек для Loop и сохранения в Ритмы.
  final List<GestureSample> _fullTrack = <GestureSample>[];
  final GlobalKey<_GestureCanvasState> _canvasKey = GlobalKey<_GestureCanvasState>();

  bool _looping = false;
  double _speed = 1.0;
  Timer? _loopTimer;
  int _loopPos = 0;
  final Stopwatch _loopClock = Stopwatch();

  /// «Живая отправка»: рисование сразу управляет устройством (как в
  /// LoveSpouse — водишь пальцем, мотор меняет мощность). Включено по
  /// умолчанию; можно выключить, чтобы только записывать жест.
  bool _liveSend = true;

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
    // Скользящее окно ~8 секунд: график всегда показывает недавнее
    // движение, а не сжимает всю историю в нечитаемую линию.
    // Для Loop и сохранения держим полный трек отдельно.
    _fullTrack.add(GestureSample(tMs, u1, u2));
    if (_fullTrack.length > 6000) _fullTrack.removeAt(0);
    const windowMs = 8000;
    while (_track.isNotEmpty && tMs - _track.first.tMs > windowMs) {
      _track.removeAt(0);
    }
    if (channels.isEmpty) return;
    // Команды уходят только в «живом» режиме; иначе жест лишь пишется.
    if (!_liveSend) {
      _canvasKey.currentState?._repaint();
      return;
    }
    if (_is2D) {
      widget.onCommand(channels[0].id, u1.clamp(0.0, 1.0));
      if (channels.length > 1) {
        widget.onCommand(channels[1].id, u2.clamp(0.0, 1.0));
      }
    } else {
      // 1D: уровень на все моторы сразу.
      if (widget.onAll != null) {
        widget.onAll!(u1.clamp(0.0, 1.0));
      } else {
        widget.onCommand(channels[0].id, u1.clamp(0.0, 1.0));
      }
    }
    _canvasKey.currentState?._repaint();
  }

  void _toggleLoop() {
    if (_fullTrack.length < 2) return;
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
      if (_fullTrack.isEmpty) return;
      final virtualMs = _loopClock.elapsedMilliseconds * _speed;
      final total = _fullTrack.last.tMs == 0 ? 1 : _fullTrack.last.tMs;
      final pos = virtualMs % total;
      // Ближайшая точка полного трека.
      var idx = (pos / total * (_fullTrack.length - 1)).round();
      idx = idx.clamp(0, _fullTrack.length - 1);
      if (idx != _loopPos || virtualMs % total < tickMs * _speed) {
        _loopPos = idx;
        final s = _fullTrack[idx];
        final channels = widget.device.channels;
        if (channels.isNotEmpty) {
          if (_is2D) {
            widget.onCommand(channels[0].id, s.u1);
            if (channels.length > 1) {
              widget.onCommand(channels[1].id, s.u2);
            }
          } else if (widget.onAll != null) {
            widget.onAll!(s.u1);
          } else {
            widget.onCommand(channels[0].id, s.u1);
          }
        }
      }
      _canvasKey.currentState?._repaint();
    });
  }

  void _saveToRhythms() {
    widget.onSaveToRhythms?.call(List<GestureSample>.of(_fullTrack));
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
              loopProgress: _looping && _fullTrack.length > 1 ? _loopPos / (_fullTrack.length - 1) : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _liveSend
                      ? 'Рисунок сразу управляет устройством'
                      : 'Рисунок только записывается — нажми Loop, чтобы запустить',
                  style: TextStyle(
                    fontSize: 12,
                    color: NoctwaveColors.of(context).textSecondary,
                  ),
                ),
              ),
              Switch(
                value: _liveSend,
                onChanged: (v) => setState(() => _liveSend = v),
              ),
            ],
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
                        _looping ? NoctwavePalette.accentHigh : Theme.of(context).colorScheme.primary,
                  ),
                  icon: Icon(_looping ? Icons.stop_circle_outlined : Icons.loop),
                  label: Text(_looping ? 'Стоп Loop' : 'Loop'),
                  onPressed: _fullTrack.length < 2 ? null : _toggleLoop,
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
                onPressed: _fullTrack.length < 2 ? null : _saveToRhythms,
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
            accent: Theme.of(context).colorScheme.primary,
            gridColor: NoctwaveColors.of(context).outline,
          ),
        );
        return GestureDetector(
          onPanUpdate: (d) => _handlePan(d, constraints),
          onPanEnd: (_) {},
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: NoctwaveColors.of(context).surface,
                border: Border.all(color: NoctwaveColors.of(context).outline),
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
  _TrackPainter({
    required this.is2D,
    required this.track,
    this.loopProgress,
    required this.accent,
    required this.gridColor,
  });

  final bool is2D;
  final List<GestureSample> track;
  final double? loopProgress;
  final Color accent;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Сетка.
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
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
      ..color = accent
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
