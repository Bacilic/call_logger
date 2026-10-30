import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Μέγεθος γραμμάτων κειμένου στον χάρτη, σε εκατοστά πραγματικού χώρου.
const double kFloorPlanTextSizeMinCm = 10;
const double kFloorPlanTextSizeMaxCm = 300;

/// Κάθε A− / A+ αλλάζει το μέγεθος κατά 15%: ίδια αίσθηση βήματος σε μικρά και
/// μεγάλα γράμματα.
const double _kSizeStepFactor = 1.15;

/// Τα γράμματα του πλαισίου δεν μικραίνουν κάτω από αυτό, ώστε να διαβάζεται
/// ό,τι γράφεται ακόμη κι όταν ο χάρτης είναι μακριά.
const double _kMinEditFontPx = 14;

const double _kBarHeight = 40;
const double _kBarGap = 4;
const EdgeInsets _kFieldPadding = EdgeInsets.symmetric(
  horizontal: 8,
  vertical: 4,
);

/// Το επόμενο μέγεθος μετά από ένα A+ ([increase]) ή A−, μέσα στα όρια.
double stepFloorPlanTextSize(double cm, {required bool increase}) {
  final next = increase ? cm * _kSizeStepFactor : cm / _kSizeStepFactor;
  return next.clamp(kFloorPlanTextSizeMinCm, kFloorPlanTextSizeMaxCm);
}

/// Πόσα pixel έχουν τα γράμματα του πλαισίου για κείμενο [sizeCm] σε ζουμ
/// [pixelsPerCm] — το πραγματικό μέγεθος στον χάρτη, με κατώτατο όριο.
double floorPlanTextEditFontPx(double sizeCm, double pixelsPerCm) =>
    math.max(_kMinEditFontPx, sizeCm * pixelsPerCm);

/// Πού μπαίνει το πάνω αριστερό του πλαισίου ώστε το κέντρο του πεδίου να
/// πέσει στο [center] της οθόνης, για το [text] όπως είναι όταν ανοίγει.
Offset floorPlanTextEditorTopLeft(Offset center, String text, double fontPx) {
  final painter = TextPainter(
    text: TextSpan(
      text: text.isEmpty ? ' ' : text,
      style: TextStyle(fontSize: fontPx, height: 1.25),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final field = Size(
    math.max(160, painter.width + _kFieldPadding.horizontal + 4),
    painter.height + _kFieldPadding.vertical + 4,
  );
  painter.dispose();
  return center -
      Offset(field.width / 2, field.height / 2 + _kBarHeight + _kBarGap);
}

/// Πλαίσιο κειμένου πάνω στον χάρτη: γράφεται επιτόπου, με τη μικρή μπάρα
/// A− / μέγεθος / A+ / ✕ / ✓ ακριβώς από πάνω.
///
/// Enter αλλάζει γραμμή· Ctrl+Enter ή ✓ αποθηκεύει· Esc ή ✕ ακυρώνει. Το
/// κλικ έξω από το πλαίσιο το χειρίζεται η οθόνη (αποθηκεύει).
class FloorPlanTextEditor extends StatefulWidget {
  const FloorPlanTextEditor({
    super.key,
    required this.initialText,
    required this.initialSizeCm,
    required this.pixelsPerCm,
    required this.fieldKey,
    required this.onCommit,
    required this.onCancel,
  });

  final String initialText;
  final double initialSizeCm;
  final double pixelsPerCm;

  /// Το κλειδί του πεδίου: από αυτό η οθόνη βρίσκει πού ακριβώς είναι το
  /// κείμενο τη στιγμή της αποθήκευσης.
  final GlobalKey fieldKey;

  final void Function(String text, double sizeCm) onCommit;
  final VoidCallback onCancel;

  @override
  State<FloorPlanTextEditor> createState() => FloorPlanTextEditorState();
}

class FloorPlanTextEditorState extends State<FloorPlanTextEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  )..selection = TextSelection.collapsed(offset: widget.initialText.length);
  late double _sizeCm = widget.initialSizeCm.clamp(
    kFloorPlanTextSizeMinCm,
    kFloorPlanTextSizeMaxCm,
  );

  /// Ό,τι γράφει αυτή τη στιγμή το πλαίσιο — για αποθήκευση από έξω (κλικ
  /// έξω από το πλαίσιο).
  ({String text, double sizeCm}) get current =>
      (text: _text.text, sizeCm: _sizeCm);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _step({required bool increase}) => setState(
    () => _sizeCm = stepFloorPlanTextSize(_sizeCm, increase: increase),
  );

  void _commit() => widget.onCommit(_text.text, _sizeCm);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontPx = floorPlanTextEditFontPx(_sizeCm, widget.pixelsPerCm);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _commit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _commit,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _kBarHeight,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surface,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Μικρότερα γράμματα',
                    onPressed: _sizeCm > kFloorPlanTextSizeMinCm
                        ? () => _step(increase: false)
                        : null,
                    icon: const Text('A−', style: TextStyle(fontSize: 14)),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${_sizeCm.round()} εκ.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Μεγαλύτερα γράμματα',
                    onPressed: _sizeCm < kFloorPlanTextSizeMaxCm
                        ? () => _step(increase: true)
                        : null,
                    icon: const Text('A+', style: TextStyle(fontSize: 17)),
                  ),
                  const SizedBox(height: 24, child: VerticalDivider(width: 9)),
                  IconButton(
                    tooltip: 'Ακύρωση (Esc)',
                    onPressed: widget.onCancel,
                    icon: Icon(Icons.close, color: theme.colorScheme.error),
                  ),
                  IconButton(
                    tooltip: 'Αποθήκευση (Ctrl+Enter)',
                    onPressed: _commit,
                    icon: const Icon(Icons.check, color: Colors.green),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: _kBarGap),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 640),
            child: IntrinsicWidth(
              child: Material(
                key: widget.fieldKey,
                color: theme.colorScheme.surface.withValues(alpha: 0.92),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  style: TextStyle(
                    fontSize: fontPx,
                    height: 1.25,
                    color: Colors.black87,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: _kFieldPadding,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Enter: νέα γραμμή · Ctrl+Enter: αποθήκευση · Esc: ακύρωση',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
