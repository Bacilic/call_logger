// Διάλογος πρότασης παρόμοιου τμήματος — χωρίς πραγματική βάση.
//
//   flutter test test/features/directory/similar_department_suggestion_dialog_test.dart --timeout 30s

import 'package:call_logger/core/utils/similar_department_finder.dart';
import 'package:call_logger/core/widgets/draggable_dialog_shell.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/similar_department_suggestion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  SimilarDepartmentDialogResult? lastResult;

  Future<void> pumpDialog(
    WidgetTester tester, {
    required String typedName,
    required List<SimilarDepartmentMatch> matches,
  }) async {
    lastResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                lastResult = await showDialog<SimilarDepartmentDialogResult>(
                  context: context,
                  builder: (_) => SimilarDepartmentSuggestionDialog(
                    typedName: typedName,
                    matches: matches,
                  ),
                );
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

  SimilarDepartmentMatch match(String name, {int id = 1, int score = 80}) {
    return SimilarDepartmentMatch(
      department: DepartmentModel(id: id, name: name),
      score: score,
    );
  }

  testWidgets('δείχνει τι πληκτρολογήθηκε και τι υπάρχει, με ετικέτες', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      typedName: 'Γραφείο Πληροφορικής',
      matches: [match('Πληροφορική')],
    );

    expect(find.text('Μήπως εννοείτε υπάρχον τμήμα;'), findsOneWidget);
    expect(
      find.text('Πληκτρολογήσατε'),
      findsOneWidget,
      reason: greekExpectMsg('Ο διάλογος δείχνει τι πληκτρολόγησε ο χρήστης'),
    );
    expect(find.text('Υπάρχει ήδη'), findsOneWidget);
    expect(
      find.text('Γραφείο Πληροφορικής', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Πληροφορική', findRichText: true), findsOneWidget);
    expect(find.text('Όχι, δημιουργία νέου τμήματος'), findsOneWidget);
    expect(find.text('Ακύρωση'), findsOneWidget);
  });

  testWidgets('ο διάλογος είναι μετακινήσιμος', (tester) async {
    await pumpDialog(
      tester,
      typedName: 'Γραφείο Πληροφορικής',
      matches: [match('Πληροφορική')],
    );

    expect(
      find.byType(DraggableDialogShell),
      findsOneWidget,
      reason: greekExpectMsg(
        'Ο διάλογος «Μήπως εννοείτε υπάρχον τμήμα;» πρέπει να μετακινείται '
        'για να φαίνεται η φόρμα από πίσω',
      ),
    );
  });

  testWidgets('πάτημα σε υπάρχον τμήμα επιστρέφει την επιλογή του', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      typedName: 'Γραφείο Πληροφορικής',
      matches: [match('Πληροφορική', id: 9)],
    );

    await tester.tap(find.text('Πληροφορική', findRichText: true));
    await tester.pumpAndSettle();

    expect(
      lastResult?.selectedDepartment?.id,
      9,
      reason: greekExpectMsg(
        'Το πάτημα στη γραμμή του υπάρχοντος επιστρέφει το τμήμα',
      ),
    );
  });

  testWidgets('«Όχι, δημιουργία νέου τμήματος» επιστρέφει createNew', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      typedName: 'Γραφείο Πληροφορικής',
      matches: [match('Πληροφορική')],
    );

    await tester.tap(find.text('Όχι, δημιουργία νέου τμήματος'));
    await tester.pumpAndSettle();

    expect(lastResult?.createNew, isTrue);
  });

  testWidgets('πολλά ταιριάσματα — όλα εμφανίζονται, μία ετικέτα', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      typedName: 'Γραμματεία',
      matches: [match('Γραμματεία ΤΕΙ', id: 1), match('Γραμματεία ΤΕΠ', id: 2)],
    );

    expect(find.text('Υπάρχουν ήδη'), findsOneWidget);
    expect(find.text('Γραμματεία ΤΕΙ', findRichText: true), findsOneWidget);
    expect(find.text('Γραμματεία ΤΕΠ', findRichText: true), findsOneWidget);
  });
}
