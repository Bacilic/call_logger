import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Αιωρούμενο στοιχείο για περιστροφή κατόψης (glassmorphism), πάνω από τον καμβά.
class MapRotationPod extends StatefulWidget {
  const MapRotationPod({
    super.key,
    required this.rotationDegrees,
    required this.onRotationChanged,
    required this.onRotationChangeEnd,
    this.enabled = true,
  });

  final double rotationDegrees;
  final ValueChanged<double> onRotationChanged;
  final ValueChanged<double> onRotationChangeEnd;
  final bool enabled;

  @override
  State<MapRotationPod> createState() => _MapRotationPodState();
}

class _MapRotationPodState extends State<MapRotationPod> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.rotationDegrees.round().toString(),
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant MapRotationPod oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotationDegrees != widget.rotationDegrees) {
      if (!_focusNode.hasFocus && !_isDragging) {
        _controller.text = widget.rotationDegrees.round().toString();
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commitText();
    }
  }

  void _commitText() {
    if (!widget.enabled) return;
    final text = _controller.text.trim();
    final val = double.tryParse(text);
    if (val != null) {
      _fireDirectCommit(val);
    } else {
      _controller.text = widget.rotationDegrees.round().toString();
    }
  }

  double _normalizeDegrees(double v) {
    var x = v % 360.0;
    if (x < 0) x += 360.0;
    return x;
  }

  void _fireChange(double value) {
    if (!widget.enabled) return;
    widget.onRotationChanged(_normalizeDegrees(value));
  }

  void _fireChangeEnd(double value) {
    if (!widget.enabled) return;
    widget.onRotationChangeEnd(_normalizeDegrees(value));
  }

  void _fireDirectCommit(double value) {
    if (!widget.enabled) return;
    final n = _normalizeDegrees(value);
    widget.onRotationChanged(n);
    widget.onRotationChangeEnd(n);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!widget.enabled) return;
    if (event is PointerScrollEvent) {
      final delta = event.scrollDelta.dy;
      final step = 5.0;
      final newRot = widget.rotationDegrees + (delta > 0 ? -step : step);
      _fireDirectCommit(newRot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassTint = isDark
        ? Colors.black.withValues(alpha: 0.62)
        : Colors.white.withValues(alpha: 0.72);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);

    final display = widget.rotationDegrees.clamp(0.0, 360.0);

    Widget pod = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: 160,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: glassTint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Tooltip(
                message: 'Περιστροφή (μοίρες) - Επιτρέπεται και αρνητική',
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: false,
                  ),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                    suffixText: '°',
                    border: InputBorder.none,
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  onSubmitted: (_) => _commitText(),
                ),
              ),
              const SizedBox(height: 4),
              Listener(
                onPointerSignal: _handlePointerSignal,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                  ),
                  child: Slider(
                    min: 0,
                    max: 360,
                    value: display,
                    onChangeStart: widget.enabled
                        ? (_) {
                            setState(() => _isDragging = true);
                          }
                        : null,
                    onChanged: widget.enabled
                        ? (v) {
                            _controller.text = v.round().toString();
                            _fireChange(v);
                          }
                        : null,
                    onChangeEnd: widget.enabled
                        ? (v) {
                            setState(() => _isDragging = false);
                            _fireChangeEnd(v);
                          }
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Επαναφορά 0°',
                    onPressed: widget.enabled ? () => _fireDirectCommit(0) : null,
                    icon: const Icon(Icons.restart_alt_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: '−90° (αριστερόστροφα)',
                    onPressed: widget.enabled
                        ? () => _fireDirectCommit(widget.rotationDegrees - 90)
                        : null,
                    icon: const Icon(Icons.rotate_left_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: '+90° (δεξιόστροφα)',
                    onPressed: widget.enabled
                        ? () => _fireDirectCommit(widget.rotationDegrees + 90)
                        : null,
                    icon: const Icon(Icons.rotate_right_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.enabled) {
      pod = Opacity(opacity: 0.45, child: pod);
    }

    return pod;
  }
}
