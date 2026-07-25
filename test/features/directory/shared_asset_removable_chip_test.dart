// Chip κοινόχρηστου στοιχείου: ενεργό / νεοπροστεθέν / προς αφαίρεση.
//
//   flutter test test/features/directory/shared_asset_removable_chip_test.dart

import 'package:call_logger/features/directory/screens/widgets/department_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('(α) κανονική κατάσταση: χωρίς διαγραφή, εικονίδιο X', (
    tester,
  ) async {
    var toggled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemovableSharedChip(
            label: '2310123456',
            isNewlyAdded: false,
            isPendingRemoval: false,
            onToggle: () => toggled = true,
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('2310123456'));
    expect(label.style?.decoration, isNot(TextDecoration.lineThrough));
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsNothing);
    expect(toggled, isFalse);
  });

  testWidgets(
    '(β) pendingRemoval: διαγραμμένο, κόκκινο φόντο, undo + tooltip',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemovableSharedChip(
              label: 'EQ-1001',
              isNewlyAdded: false,
              isPendingRemoval: true,
              onToggle: () {},
            ),
          ),
        ),
      );

      final label = tester.widget<Text>(find.text('EQ-1001'));
      expect(label.style?.decoration, TextDecoration.lineThrough);

      final chip = tester.widget<InputChip>(find.byType(InputChip));
      expect(chip.backgroundColor, Colors.red.shade100);
      expect(
        chip.deleteButtonTooltipMessage,
        'Θα αφαιρεθεί στην αποθήκευση — κλικ για επαναφορά',
      );
      expect(find.byIcon(Icons.undo), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsNothing);
    },
  );

  testWidgets('(γ) πάτημα εικονιδίου καλεί onToggle', (tester) async {
    var toggled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemovableSharedChip(
            label: '2898',
            isNewlyAdded: true,
            isPendingRemoval: false,
            onToggle: () => toggled = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();
    expect(toggled, isTrue);
  });
}
