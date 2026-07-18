// Widget tests: διάλογος σύγκρουσης τοποθεσίας τηλεφώνου (μετακινούμενος).
//
//   flutter test test/features/directory/screens/widgets/user_phone_department_conflict_dialog_test.dart

import 'package:call_logger/core/directory/phone_department_policy.dart';
import 'package:call_logger/core/widgets/draggable_dialog_shell.dart';
import 'package:call_logger/features/directory/screens/widgets/user_phone_department_conflict_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_reporter.dart';

const _titleText = 'Σύγκρουση τοποθεσίας τηλεφώνου';

PhoneDepartmentConflict _sampleConflict() {
  return const PhoneDepartmentConflict(
    phone: '2511',
    existingDepartmentId: 7,
    existingDepartmentName: 'Αιμοδοσία',
    otherUserOwnerLabels: ['Σοφία Σπυροπούλου (Αιμοδοσία)'],
    hasDepartmentLocationConflict: true,
    hasOtherUserOwners: true,
  );
}

Future<void> _openConflictDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showUserPhoneDepartmentConflictDialog(
                    context,
                    conflicts: [_sampleConflict()],
                    userDisplayName: 'Φαρμακοποιός 1',
                    targetDepartmentName: 'Φαρμακείο',
                    targetDepartmentId: 3,
                  );
                },
                child: const Text('Άνοιγμα'),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Άνοιγμα'));
  await tester.pumpAndSettle();
}

Offset _shellTranslateOffset(WidgetTester tester) {
  // Το κέλυφος έχει το εξωτερικό Transform· το AlertDialog μπορεί να έχει κι άλλα.
  final transforms = tester.widgetList<Transform>(
    find.descendant(
      of: find.byType(DraggableDialogShell),
      matching: find.byType(Transform),
    ),
  );
  final transform = transforms.first;
  final m4 = transform.transform;
  return Offset(m4.storage[12], m4.storage[13]);
}

void main() {
  group('UserPhoneDepartmentConflictDialog · μετακίνηση', () {
    testWidgets('τυλίγεται σε DraggableDialogShell με τον τίτλο σύγκρουσης', (
      tester,
    ) async {
      await _openConflictDialog(tester);

      expect(
        find.byType(DraggableDialogShell),
        findsOneWidget,
        reason: greekExpectMsg(
          'Ο διάλογος σύγκρουσης πρέπει να χρησιμοποιεί DraggableDialogShell',
        ),
      );
      expect(find.text(_titleText), findsOneWidget);
      expect(
        _shellTranslateOffset(tester),
        Offset.zero,
        reason: greekExpectMsg('Αρχική μετατόπιση μηδενική'),
      );
    });

    testWidgets('σύρσιμο από τον τίτλο μετακινεί τον διάλογο σύγκρουσης', (
      tester,
    ) async {
      await _openConflictDialog(tester);

      const delta = Offset(40, 28);
      await tester.drag(find.text(_titleText), delta);
      await tester.pump();

      final offset = _shellTranslateOffset(tester);
      expect(
        offset.dx,
        closeTo(delta.dx, 0.5),
        reason: greekExpectMsg(
          'Το σύρσιμο από τον τίτλο πρέπει να μετακινεί τον διάλογο',
        ),
      );
      expect(
        offset.dy,
        closeTo(delta.dy, 0.5),
        reason: greekExpectMsg(
          'Το σύρσιμο από τον τίτλο πρέπει να μετακινεί τον διάλογο',
        ),
      );
    });
  });
}
