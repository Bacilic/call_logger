// Διάλογος πρότασης παρόμοιου τμήματος — χωρίς πραγματική βάση.
//
//   flutter test test/features/directory/similar_department_suggestion_dialog_test.dart --timeout 30s

import 'package:call_logger/core/utils/similar_department_finder.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/similar_department_suggestion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('εμφανίζει τίτλο, όνομα προτεινόμενου τμήματος και κουμπί νέου', (
    tester,
  ) async {
    final match = SimilarDepartmentMatch(
      department: DepartmentModel(id: 1, name: 'Γραφείο Προσωπικού'),
      score: 80,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<SimilarDepartmentDialogResult>(
                  context: context,
                  builder: (_) => SimilarDepartmentSuggestionDialog(
                    typedName: 'Προσωπικού',
                    matches: [match],
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

    expect(find.text('Μήπως εννοείτε υπάρχον τμήμα;'), findsOneWidget);
    expect(find.textContaining('Γραφείο Προσωπικού'), findsWidgets);
    expect(find.text('Όχι, δημιουργία νέου τμήματος'), findsOneWidget);
    expect(find.text('Ακύρωση'), findsOneWidget);
  });
}
