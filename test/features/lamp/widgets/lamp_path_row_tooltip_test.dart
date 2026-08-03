// Η υπόδειξη (ⓘ) των διαδρομών της Λάμπας περνά από το κοινό πρότυπο πλάτους.
//
//   flutter test test/features/lamp/widgets/lamp_path_row_tooltip_test.dart

import 'package:call_logger/core/widgets/compact_tooltip.dart';
import 'package:call_logger/features/lamp/controllers/lamp_path_management.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController(text: r'C:\Data\lamp.db'));
  tearDown(() => controller.dispose());

  Future<void> pumpRow(WidgetTester tester, {String? infoTooltip}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LampPathRow(
            controller: controller,
            label: 'Βάση Δεδομένων που χρησιμοποιεί η Λάμπα',
            infoTooltip: infoTooltip,
            onPick: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('η υπόδειξη διαδρομής χρησιμοποιεί το κοινό πρότυπο', (
    tester,
  ) async {
    await pumpRow(tester, infoTooltip: 'Μακροσκελής υπόδειξη προς αναδίπλωση.');

    final compact = tester.widget<CompactTooltip>(
      find.byType(CompactTooltip),
    );
    expect(compact.message, 'Μακροσκελής υπόδειξη προς αναδίπλωση.');
  });

  testWidgets('χωρίς κείμενο υπόδειξης δεν εμφανίζεται εικονίδιο', (
    tester,
  ) async {
    await pumpRow(tester);

    expect(find.byType(CompactTooltip), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('το πλάτος της υπόδειξης δεν ξεπερνά το όριο του προτύπου', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final maxWidth = CompactTooltip.maxWidthFor(context);
            final screenWidth = MediaQuery.sizeOf(context).width;
            expect(maxWidth, lessThanOrEqualTo(360));
            expect(maxWidth, greaterThanOrEqualTo(220));
            expect(maxWidth, lessThan(screenWidth));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
