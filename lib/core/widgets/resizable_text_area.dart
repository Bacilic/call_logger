import 'package:flutter/material.dart';

import 'compact_tooltip.dart';
import 'lexicon_spell_text_form_field.dart';
import 'spell_check_controller.dart';

/// Η λαβή αλλαγής ύψους — σταθερό κλειδί ώστε να εντοπίζεται από τους ελέγχους.
const Key resizeGripKey = ValueKey('resizable_text_area_grip');

/// Πολύγραμμο πεδίο που μεγαλώνει μόνο του και σέρνεται από την κάτω γωνία.
///
/// Το Flutter δεν έχει έτοιμη λαβή αλλαγής μεγέθους — τη δίνει μόνο το
/// `<textarea>` του browser. Εδώ συνδυάζονται οι δύο συμπεριφορές:
///
/// - **Αυτόματα:** το πεδίο ξεκινά στις [minLines] και ανοίγει καθώς γράφετε
///   ως τις [autoGrowMaxLines]· από εκεί και πέρα κυλάει εσωτερικά.
/// - **Χειροκίνητα:** μόλις συρθεί η λαβή, το ύψος το ορίζετε εσείς και δεν
///   ξανα-υπολογίζεται από το κείμενο. Διπλό κλικ στη λαβή επαναφέρει το
///   αυτόματο ύψος.
///
/// Το ύψος ζει όσο ζει το widget: δεν αποθηκεύεται, όπως και στο `<textarea>`.
class ResizableTextArea extends StatefulWidget {
  const ResizableTextArea({
    super.key,
    required this.controller,
    required this.decoration,
    this.minLines = 3,
    this.autoGrowMaxLines = 10,
    this.maxDragHeight = 520,
    this.textCapitalization = TextCapitalization.sentences,
    this.validator,
    this.onChanged,
    this.focusNode,
    this.enabled,
  }) : assert(minLines >= 1),
       assert(autoGrowMaxLines >= minLines);

  final SpellCheckController controller;
  final InputDecoration decoration;

  /// Ύψος εκκίνησης, σε γραμμές.
  final int minLines;

  /// Ως πού μεγαλώνει μόνο του πριν αρχίσει να κυλάει.
  final int autoGrowMaxLines;

  /// Ανώτατο ύψος που μπορεί να φτάσει το σύρσιμο, σε pixel.
  final double maxDragHeight;

  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool? enabled;

  @override
  State<ResizableTextArea> createState() => _ResizableTextAreaState();
}

class _ResizableTextAreaState extends State<ResizableTextArea> {
  /// `null` όσο το ύψος προκύπτει από το κείμενο.
  double? _draggedHeight;

  /// Ύψος του πεδίου την ώρα που ξεκίνησε το σύρσιμο — η αφετηρία της κίνησης.
  double? _dragStartHeight;

  final _fieldKey = GlobalKey();

  /// Ελάχιστο ύψος: όσο πιάνουν οι [ResizableTextArea.minLines] γραμμές.
  double _minHeightFor(BuildContext context) {
    final style =
        widget.decoration.hintStyle ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16);
    final lineHeight = (style.fontSize ?? 16) * (style.height ?? 1.4);
    // Το περίγραμμα και το εσωτερικό περιθώριο του πεδίου, χονδρικά.
    const chrome = 32.0;
    return lineHeight * widget.minLines + chrome;
  }

  void _onDragStart(DragStartDetails _) {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    _dragStartHeight = _draggedHeight ?? box?.size.height;
  }

  void _onDragUpdate(DragUpdateDetails details, double minHeight) {
    final start = _dragStartHeight;
    if (start == null) return;
    setState(() {
      _draggedHeight = (start + details.localPosition.dy).clamp(
        minHeight,
        widget.maxDragHeight,
      );
    });
  }

  void _resetToAuto() {
    setState(() {
      _draggedHeight = null;
      _dragStartHeight = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final minHeight = _minHeightFor(context);
    final fixedHeight = _draggedHeight;

    final field = fixedHeight == null
        ? LexiconSpellTextFormField(
            key: _fieldKey,
            controller: widget.controller,
            decoration: widget.decoration,
            validator: widget.validator,
            textCapitalization: widget.textCapitalization,
            minLines: widget.minLines,
            maxLines: widget.autoGrowMaxLines,
            onChanged: widget.onChanged,
            focusNode: widget.focusNode,
            enabled: widget.enabled,
          )
        : SizedBox(
            key: _fieldKey,
            height: fixedHeight,
            child: LexiconSpellTextFormField(
              controller: widget.controller,
              decoration: widget.decoration,
              validator: widget.validator,
              textCapitalization: widget.textCapitalization,
              minLines: null,
              maxLines: null,
              expands: true,
              onChanged: widget.onChanged,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
            ),
          );

    return Stack(
      children: [
        field,
        Positioned(
          right: 2,
          bottom: 2,
          child: _ResizeGrip(
            key: resizeGripKey,
            onDragStart: _onDragStart,
            onDragUpdate: (d) => _onDragUpdate(d, minHeight),
            onDoubleTap: _resetToAuto,
            isManual: fixedHeight != null,
          ),
        ),
      ],
    );
  }
}

/// Η λαβή: δύο διαγώνιες γραμμές στην κάτω δεξιά γωνία, όπως στο `<textarea>`.
class _ResizeGrip extends StatelessWidget {
  const _ResizeGrip({
    super.key,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDoubleTap,
    required this.isManual,
  });

  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDoubleTap;

  /// Όταν το ύψος ορίστηκε με το χέρι, η λαβή τονίζεται και η υπόδειξη
  /// αναφέρει τον τρόπο επαναφοράς.
  final bool isManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CompactTooltip(
      message: isManual
          ? 'Σύρετε για αλλαγή ύψους — διπλό κλικ για αυτόματο'
          : 'Σύρετε για αλλαγή ύψους',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: onDragStart,
          onVerticalDragUpdate: onDragUpdate,
          onDoubleTap: onDoubleTap,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CustomPaint(
              painter: _GripPainter(
                color: isManual
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GripPainter extends CustomPainter {
  const _GripPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    // Δύο διαγώνιες, η εξωτερική κοντύτερη — το καθιερωμένο σχήμα λαβής.
    canvas.drawLine(
      Offset(size.width - 3, size.height - 11),
      Offset(size.width - 11, size.height - 3),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 3, size.height - 6),
      Offset(size.width - 6, size.height - 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GripPainter oldDelegate) => oldDelegate.color != color;
}
