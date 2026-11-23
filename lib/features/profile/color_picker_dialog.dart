import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/theme/noctwave_theme.dart';

/// Диалог выбора произвольного акцентного цвета: HSV-поле
/// (оттенок × насыщенность), слайдер яркости и HEX-поле.
/// Без внешних зависимостей — рисуется CustomPaint.
Future<Color?> showColorPicker(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _ColorPickerDialog(initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hexController =
      TextEditingController(text: _hexOf(widget.initial));

  static String _hexOf(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  void _setHex(String text) {
    final clean = text.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    if (clean.length == 6) {
      final value = int.tryParse(clean, radix: 16);
      if (value != null) {
        setState(() {
          _hsv = HSVColor.fromColor(Color(0xFF000000 | value));
        });
      }
    }
  }

  void _onField(Offset local, Size size) {
    final hue = (local.dx / size.width).clamp(0.0, 1.0) * 360;
    final sat = 1.0 - (local.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      _hsv = _hsv.withHue(hue).withSaturation(sat);
      _hexController.text = _hexOf(_hsv.toColor());
    });
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NoctwaveColors.of(context);
    final current = _hsv.toColor();
    return AlertDialog(
      backgroundColor: colors.surface,
      title: const Text('Свой цвет'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // HSV-поле: оттенок по X, насыщенность по Y.
            LayoutBuilder(
              builder: (context, constraints) {
                const height = 160.0;
                return GestureDetector(
                  onPanDown: (d) =>
                      _onField(d.localPosition, Size(constraints.maxWidth, height)),
                  onPanUpdate: (d) =>
                      _onField(d.localPosition, Size(constraints.maxWidth, height)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, height),
                      painter: _HsvFieldPainter(value: _hsv.value),
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: height,
                        child: Align(
                          alignment: Alignment(
                            (_hsv.hue / 360) * 2 - 1,
                            (1 - _hsv.saturation) * 2 - 1,
                          ),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              color: current,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            // Яркость.
            Row(
              children: <Widget>[
                const Icon(Icons.brightness_6, size: 18),
                Expanded(
                  child: Slider(
                    value: _hsv.value,
                    onChanged: (v) {
                      setState(() {
                        _hsv = _hsv.withValue(v);
                        _hexController.text = _hexOf(_hsv.toColor());
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: current,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.outline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    decoration: const InputDecoration(
                      labelText: 'HEX',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: _setHex,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, current),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

/// Рисует поле оттенок×насыщенность при фиксированной яркости.
class _HsvFieldPainter extends CustomPainter {
  _HsvFieldPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    // Горизонтальный градиент оттенка.
    const hueStops = <Color>[
      Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
      Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
      Color(0xFFFF0000),
    ];
    final hueRect = Offset.zero & size;
    final hueShader = LinearGradient(colors: hueStops).createShader(hueRect);
    canvas.drawRect(hueRect, Paint()..shader = hueShader);
    // Вертикальный градиент насыщенности: белый сверху → прозрачный.
    final satShader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Colors.white, Color(0x00FFFFFF)],
    ).createShader(hueRect);
    canvas.drawRect(hueRect, Paint()..shader = satShader);
    // Затемнение по яркости.
    canvas.drawRect(
      hueRect,
      Paint()..color = Colors.black.withValues(alpha: 1 - value),
    );
  }

  @override
  bool shouldRepaint(covariant _HsvFieldPainter old) => old.value != value;
}
