import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/theme/noctwave_theme.dart';

/// Оверлей «OLED-замок» (ТЗ 3.2.4): истинный чёрный #000000, сверхтусклые
/// часы, индикатор активного режима, блокировка случайных касаний,
/// разблокировка долгим тапом 1.5 сек или свайпом вправо.
///
/// Удерживает экран активным: Flutter-уровень — через
/// `SystemChrome.setEnabledSystemUIMode`; нативный Wakelock /
/// isIdleTimerDisabled подключается плагином на Этапе 1.
class OledLockOverlay extends StatefulWidget {
  const OledLockOverlay({
    super.key,
    required this.modeLabel,
    required this.txActive,
    required this.onUnlock,
    required this.onVolumeStop,
  });

  final String modeLabel;
  final bool txActive;
  final VoidCallback onUnlock;
  final Future<void> Function() onVolumeStop;

  @override
  State<OledLockOverlay> createState() => _OledLockOverlayState();
}

class _OledLockOverlayState extends State<OledLockOverlay> {
  Timer? _clock;
  DateTime _now = DateTime.now();
  double _holdProgress = 0;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // Отключаем системный UI — полный иммерсивный режим.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _holdTimer?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _startHold() {
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      setState(() => _holdProgress += 50 / 1500);
      if (_holdProgress >= 1) {
        t.cancel();
        widget.onUnlock();
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    setState(() => _holdProgress = 0);
  }

  String _clockText() {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    // AbsorbPointer блокирует случайные касания всего, кроме зоны
    // разблокировки. Фон — строго #000000 (OLED, ТЗ 8.4).
    return GestureDetector(
      // Свайп вправо — альтернативная разблокировка.
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 300) widget.onUnlock();
      },
      child: Container(
        color: NoctwavePalette.oledBlack,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              const Spacer(flex: 3),
              // Сверхтусклые часы.
              Text(
                _clockText(),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w200,
                  color: Colors.white.withValues(alpha: 0.12),
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.txActive
                          ? NoctwavePalette.accentHigh.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.modeLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.15),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 2),
              // Экстренный СТОП по кнопке «Громкость вниз» обрабатывается
              // нативным слоем (KeyEvent / rawKeyboardListener); здесь —
              // страховочная зона долгого тапа.
              GestureDetector(
                onLongPressStart: (_) => _startHold(),
                onLongPressEnd: (_) => _cancelHold(),
                onLongPressCancel: _cancelHold,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _holdProgress.clamp(0.0, 1.0),
                            child: ColoredBox(
                              color: NoctwavePalette.accentLow
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                        Center(
                          child: Text(
                            'Удерживайте 1.5 с для разблокировки',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.2),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
