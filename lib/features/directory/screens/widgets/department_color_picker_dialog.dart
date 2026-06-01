import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'department_color_palette.dart';

/// Διάλογος επιλογέα χρώματος (κορεσμός/φωτεινότητα, απόχρωση, hex).
Future<Color?> showDepartmentColorPickerDialog(
  BuildContext context, {
  required Color initialColor,
}) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => _DepartmentColorPickerDialog(initialColor: initialColor),
  );
}

class _DepartmentColorPickerDialog extends StatefulWidget {
  const _DepartmentColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_DepartmentColorPickerDialog> createState() =>
      _DepartmentColorPickerDialogState();
}

class _DepartmentColorPickerDialogState
    extends State<_DepartmentColorPickerDialog> {
  late final TextEditingController _hexController;
  late double _hue;
  late double _saturation;
  late double _value;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    _hexController = TextEditingController(text: colorToDepartmentHex(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _color =>
      HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();

  void _syncFromHsv() {
    _hexController.text = colorToDepartmentHex(_color);
  }

  void _applyHex(String raw) {
    final parsed = tryParseDepartmentHex(raw.trim());
    if (parsed == null) return;
    final hsv = HSVColor.fromColor(parsed);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _value = hsv.value;
      _syncFromHsv();
    });
  }

  void _setSv(double s, double v) {
    setState(() {
      _saturation = s.clamp(0.0, 1.0);
      _value = v.clamp(0.0, 1.0);
      _syncFromHsv();
    });
  }

  void _setHue(double h) {
    setState(() {
      _hue = h % 360;
      _syncFromHsv();
    });
  }

  void _onSvLocal(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = (1 - local.dy / size.height).clamp(0.0, 1.0);
    _setSv(s, v);
  }

  void _onHueLocal(double dx, double width) {
    _setHue((dx / width) * 360);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const pickerHeight = 140.0;
    const previewWidth = 52.0;

    return AlertDialog(
      title: const Text('Επιλογέας χρώματος'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: pickerHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: previewWidth,
                    decoration: BoxDecoration(
                      color: _color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return GestureDetector(
                          onPanDown: (d) => _onSvLocal(d.localPosition, size),
                          onPanUpdate: (d) =>
                              _onSvLocal(d.localPosition, size),
                          onTapDown: (d) => _onSvLocal(d.localPosition, size),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white,
                                        HSVColor.fromAHSV(1, _hue, 1, 1)
                                            .toColor(),
                                      ],
                                    ),
                                  ),
                                ),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black,
                                      ],
                                    ),
                                  ),
                                ),
                                _PickerThumb(
                                  saturation: _saturation,
                                  value: _value,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return GestureDetector(
                  onPanDown: (d) => _onHueLocal(d.localPosition.dx, w),
                  onPanUpdate: (d) => _onHueLocal(d.localPosition.dx, w),
                  onTapDown: (d) => _onHueLocal(d.localPosition.dx, w),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 14,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFFFF0000),
                                  Color(0xFFFFFF00),
                                  Color(0xFF00FF00),
                                  Color(0xFF00FFFF),
                                  Color(0xFF0000FF),
                                  Color(0xFFFF00FF),
                                  Color(0xFFFF0000),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: (_hue / 360) * w - 7,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: HSVColor.fromAHSV(1, _hue, 1, 1)
                                    .toColor(),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hexController,
              decoration: InputDecoration(
                labelText: 'HEX',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Αντιγραφή',
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _hexController.text),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Αντιγράφηκε το hex'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ),
              textCapitalization: TextCapitalization.characters,
              onSubmitted: _applyHex,
              onChanged: (v) {
                if (v.trim().length >= 7) _applyHex(v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _PickerThumb extends StatelessWidget {
  const _PickerThumb({
    required this.saturation,
    required this.value,
  });

  final double saturation;
  final double value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final left = saturation * constraints.maxWidth - 8;
        final top = (1 - value) * constraints.maxHeight - 8;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: left.clamp(0.0, constraints.maxWidth - 16),
              top: top.clamp(0.0, constraints.maxHeight - 16),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 2),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
