import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/models/device_profile.dart';

/// Пульсация активного элемента в такт уровню интенсивности (ТЗ 3.1):
/// активная плитка режима мягко дышит. Отключается в «Профиле».
class PulsingActive extends StatefulWidget {
  const PulsingActive({
    super.key,
    required this.intensity,
    required this.child,
    this.enabled = true,
    this.min = 0.0,
    this.max = 0.35,
  });

  /// Текущий уровень интенсивности 0..1 (управляет глубиной пульсации).
  final double intensity;
  final Widget child;
  final bool enabled;
  final double min;
  final double max;

  @override
  State<PulsingActive> createState() => _PulsingActiveState();
}

class _PulsingActiveState extends State<PulsingActive>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.enabled && widget.intensity > 0) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PulsingActive oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldRun = widget.enabled && widget.intensity > 0;
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.intensity <= 0) return widget.child;
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Дыхание: медленный синус, глубина растёт с интенсивностью.
        final t = math.sin(_controller.value * math.pi / 2);
        final depth =
            widget.min + (widget.max - widget.min) * widget.intensity.clamp(0.0, 1.0);
        final glow = accent.withValues(alpha: t * depth);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: <BoxShadow>[
              BoxShadow(color: glow, blurRadius: 18, spreadRadius: 1),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Уровень интенсивности последнего HEX команды канала (для пульсации).
double intensityOfHex(String? lastHex, DeviceChannel channel) {
  if (lastHex == null || lastHex == channel.stopCmdHex) return 0;
  final idx = channel.intensityStepsHex.indexOf(lastHex);
  if (idx <= 0 || channel.intensityStepsHex.length < 2) return 0.5;
  return (idx / (channel.intensityStepsHex.length - 1)).clamp(0.0, 1.0);
}

