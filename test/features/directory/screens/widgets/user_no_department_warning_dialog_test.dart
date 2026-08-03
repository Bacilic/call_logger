// Widget tests: φρουρός «νέος υπάλληλος χωρίς τμήμα».
//
//   flutter test test/features/directory/screens/widgets/user_no_department_warning_dialog_test.dart

import 'package:call_logger/core/widgets/draggable_dialog_shell.dart';
import 'package:call_logger/features/directory/screens/widgets/user_no_department_warning_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_reporter.dart';

void main() {
  UserNoDepartmentWarningChoice? lastChoice;
  var dialogClosed = false;

  Future<void> pumpAndOpen(WidgetTester tester) async {
    lastChoice = null;
    dialogClosed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                lastChoice = await showUserNoDepartmentWarningDialog(
                  context,
                  userDisplayName: 'Βασίλης Δροσούλης',
                );
                dialogClosed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('ονομάζει τον υπάλληλο και είναι μετακινήσιμος', (tester) async {
    await pumpAndOpen(tester);

    expect(
      find.text(
        'Ο νέος υπάλληλος «Βασίλης Δροσούλης» δεν έχει εκχωρηθεί σε τμήμα.',
      ),
      findsOneWidget,
      reason: greekExpectMsg('Η προειδοποίηση ονομάζει τον υπάλληλο'),
    );
    expect(find.byType(DraggableDialogShell), findsOneWidget);
  });

  testWidgets('«Συνέχεια χωρίς τμήμα» επιστρέφει τη συνέχιση', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.text('Συνέχεια χωρίς τμήμα'));
    await tester.pumpAndSettle();

    expect(lastChoice, UserNoDepartmentWarningChoice.continueWithoutDepartment);
  });

  testWidgets('«Εκχώρηση σε τμήμα» επιστρέφει την εκχώρηση', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.text('Εκχώρηση σε τμήμα'));
    await tester.pumpAndSettle();

    expect(lastChoice, UserNoDepartmentWarningChoice.assignToDepartment);
  });

  testWidgets('«Ακύρωση» επιστρέφει null', (tester) async {
    await pumpAndOpen(tester);

    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();

    expect(dialogClosed, isTrue);
    expect(lastChoice, isNull);
  });
}
