import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/models/floor_plan_element.dart';
import '../../../../../core/widgets/compact_tooltip.dart';

/// Το ύψος της μπάρας, για να μπει ακριβώς κάτω από την επιλογή.
const double kFloorPlanWallThicknessBarHeight = 40;

/// Το επόμενο πάχος με το κουμπί − ή +: το πλησιέστερο «στρογγυλό» βήμα προς
/// εκείνη την κατεύθυνση, μέσα στα όρια.
double stepFloorPlanWallThickness(double cm, {required bool increase}) {
  const step = kFloorPlanWallThicknessStepCm;
  final next = increase
      ? ((cm / step).floorToDouble() + 1) * step
      : ((cm / step).ceilToDouble() - 1) * step;
  return next
      .clamp(kFloorPlanWallThicknessMinCm, kFloorPlanWallThicknessMaxCm)
      .toDouble();
}

/// Διαβάζει πάχος σε εκατοστά όπως το γράφει ο χρήστης και το φέρνει μέσα
/// στα όρια· `null` για ό,τι δεν είναι θετικός αριθμός.
double? parseFloorPlanWallThickness(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value.isNaN || value <= 0) return null;
  return value
      .clamp(kFloorPlanWallThicknessMinCm, kFloorPlanWallThicknessMaxCm)
      .roundToDouble();
}

/// Η μικρή μπάρα κάτω από τους επιλεγμένους τοίχους: − / πάχος σε εκατοστά /
/// +. Το πάχος γράφεται και με το πληκτρολόγιο (Enter).
///
/// Κάθε αλλαγή γράφεται αμέσως, ως μία κίνηση αναίρεσης, σε όλους τους
/// επιλεγμένους τοίχους.
class FloorPlanWallThicknessBar extends StatefulWidget {
  const FloorPlanWallThicknessBar({
    super.key,
    required this.thicknessCm,
    required this.onChanged,
    required this.onDone,
  });

  /// Το κοινό πάχος των επιλεγμένων τοίχων· `null` όταν διαφέρουν.
  final double? thicknessCm;
  final ValueChanged<double> onChanged;

  /// Η πληκτρολόγηση τελείωσε: η εστίαση γυρίζει στον χάρτη.
  final VoidCallback onDone;

  @override
  State<FloorPlanWallThicknessBar> createState() =>
      _FloorPlanWallThicknessBarState();
}

class _FloorPlanWallThicknessBarState extends State<FloorPlanWallThicknessBar> {
  late final TextEditingController _text = TextEditingController(
    text: _shown(),
  );
  final FocusNode _focus = FocusNode(debugLabel: 'wall-thickness');

  String _shown() => widget.thicknessCm?.round().toString() ?? '';

  @override
  void didUpdateWidget(FloorPlanWallThicknessBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Όσο γράφει ο χρήστης, ό,τι έχει γράψει δεν αλλάζει κάτω από τα χέρια του.
    if (oldWidget.thicknessCm != widget.thicknessCm && !_focus.hasFocus) {
      _text.text = _shown();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final cm = parseFloorPlanWallThickness(value);
    if (cm == null) {
      _text.text = _shown();
    } else {
      _text.text = cm.round().toString();
      widget.onChanged(cm);
    }
    widget.onDone();
  }

  void _step({required bool increase}) {
    final from = widget.thicknessCm ?? kFloorPlanDefaultWallThicknessCm;
    final next = stepFloorPlanWallThickness(from, increase: increase);
    _text.text = next.round().toString();
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cm = widget.thicknessCm;
    return SizedBox(
      height: kFloorPlanWallThicknessBarHeight,
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 10),
            Text('Πάχος', style: theme.textTheme.labelMedium),
            IconButton(
              tooltip: 'Λεπτότερος τοίχος',
              onPressed: cm == null || cm > kFloorPlanWallThicknessMinCm
                  ? () => _step(increase: false)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 44,
              child: CompactTooltip(
                message:
                    'Πάχος σε εκατοστά, από '
                    '${kFloorPlanWallThicknessMinCm.round()} ως '
                    '${kFloorPlanWallThicknessMaxCm.round()} · Enter',
                child: TextField(
                  key: const ValueKey('wall-thickness-field'),
                  controller: _text,
                  focusNode: _focus,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: cm == null ? '—' : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onSubmitted: _submit,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('εκ.', style: theme.textTheme.labelMedium),
            IconButton(
              tooltip: 'Παχύτερος τοίχος',
              onPressed: cm == null || cm < kFloorPlanWallThicknessMaxCm
                  ? () => _step(increase: true)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}
