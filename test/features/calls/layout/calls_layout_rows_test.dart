// Οι γραμμές καρτών της αναπτυγμένης οθόνης κλήσεων: η απόφαση «δίπλα-δίπλα
// ή η μία κάτω από την άλλη» μετρά το πλάτος που πραγματικά έχουν οι κάρτες,
// όχι ολόκληρο το παράθυρο — η πλευρική μπάρα πλοήγησης πιάνει το δικό της.
//
//   flutter test test/features/calls/layout/calls_layout_rows_test.dart

import 'package:call_logger/features/calls/layout/calls_layout_plan.dart';
import 'package:call_logger/features/calls/layout/calls_layout_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Εργαλεία απομακρυσμένης + χάρτης + κάρτα καλούντα: χρειάζονται 828.
final _infoRow = CallsLayoutRow([
  CallsLayoutColumn.singleSlot(CallsLayoutSlot.remoteTools),
  CallsLayoutColumn.singleSlot(CallsLayoutSlot.map),
  CallsLayoutColumn.singleSlot(CallsLayoutSlot.callerCard),
]);

/// Παράθυρο [windowWidth] με πλευρική μπάρα [railWidth] και το περιθώριο
/// 16 της οθόνης κλήσεων· επιστρέφει τι αποφάσισε η γραμμή.
Future<bool> _stackedIn(
  WidgetTester tester, {
  required double windowWidth,
  required double railWidth,
}) async {
  tester.view.physicalSize = Size(windowWidth, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  bool? stacked;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: railWidth),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CallsLayoutRows(
                rows: [_infoRow],
                rowBuilder: (row, s) {
                  stacked = s;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return stacked!;
}

void main() {
  testWidgets(
    'παράθυρο 1050 με κλειστή μπάρα: μένουν 938, κάτω από το όριο — στοίβα',
    (tester) async {
      expect(
        await _stackedIn(tester, windowWidth: 1050, railWidth: 80),
        isTrue,
      );
    },
  );

  testWidgets('παράθυρο 1400 με ανοιχτή μπάρα: χωρούν δίπλα-δίπλα', (
    tester,
  ) async {
    expect(
      await _stackedIn(tester, windowWidth: 1400, railWidth: 200),
      isFalse,
    );
  });
}
