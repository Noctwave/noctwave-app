import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Оверлей «OLED-замок» (ТЗ 3.2.4).
///
/// Зачем он нужен: на iOS сворачивание приложения или блокировка экрана
/// прерывает BLE-передачу (система переносит ServiceUUIDs в overflow area).
/// Замок держит экран активным (wakelock), гасит всё лишнее до истинного
/// чёрного и блокирует случайные касания — устройство продолжает работать,
/// а телефон не светит в темноте.
///
/// Дизайн: минимализм. Только тусклые часы и едва заметная точка TX.
/// Разблокировка — удержание в любом месте 1.5 с или свайп вправо.
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

class _OledLockOverlayState extends State<OledLockOverlay>
    with SingleTickerProviderStateMixin {
  Timer? _clock;
  DateTime _now = DateTime.now();
  late final AnimationController _holdController;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onUnlock();
        }
      });
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    _holdController.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  String _clockText() {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    // Весь экран — зона удержания для разблокировки.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _holdController.forward(from: 0),
      onLongPressEnd: (_) => _holdController.reverse(),
      onLongPressCancel: () => _holdController.reverse(),
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 300) widget.onUnlock();
      },
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Stack(
          children: <Widget>[
            // Тусклые часы по центру.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _clockText(),
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w100,
                      color: Colors.white.withValues(alpha: 0.10),
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Точка TX: едва заметна, загорается при отправке.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.txActive
                          ? const Color(0xFFF43F5E).withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ],
              ),
            ),
            // Прогресс удержания — тонкое кольцо вокруг часов, без текста.
            Center(
              child: AnimatedBuilder(
                animation: _holdController,
                builder: (context, _) {
                  if (_holdController.value == 0) {
                    return const SizedBox.shrink();
                  }
                  return SizedBox(
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: _holdController.value,
                      strokeWidth: 1.5,
                      color: Colors.white.withValues(alpha: 0.18),
                      backgroundColor: Colors.transparent,
                    ),
                  );
                },
              ),
            ),
            // Подсказка внизу — видна только во время удержания.
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: AnimatedBuilder(
                animation: _holdController,
                builder: (context, _) => Opacity(
                  opacity: _holdController.value > 0 ? 1 : 0,
                  child: Text(
                    'удерживайте для разблокировки',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.25),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
