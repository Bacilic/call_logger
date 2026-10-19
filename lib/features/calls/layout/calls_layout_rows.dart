import 'package:flutter/widgets.dart';

import 'calls_layout_plan.dart';

/// Οι γραμμές καρτών της αναπτυγμένης οθόνης κλήσεων, η μία κάτω από την
/// άλλη. Για κάθε γραμμή αποφασίζει αν οι στήλες της χωρούν δίπλα-δίπλα ή
/// στοιβάζονται, και το λέει στο [rowBuilder].
///
/// Μετρά το πλάτος που του δίνει ο γονέας — όχι το παράθυρο: η οθόνη
/// κλήσεων μοιράζεται το πλάτος με την πλευρική μπάρα πλοήγησης.
class CallsLayoutRows extends StatelessWidget {
  const CallsLayoutRows({
    super.key,
    required this.rows,
    required this.rowBuilder,
  });

  final List<CallsLayoutRow> rows;
  final Widget Function(CallsLayoutRow row, bool stacked) rowBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: rowBuilder(
                  row,
                  callsLayoutShouldStackRow(contentWidth: width, row: row),
                ),
              ),
          ],
        );
      },
    );
  }
}
