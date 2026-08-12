// Κείμενο διαλόγου παρόμοιων υπαλλήλων — σκέτα UserModel, χωρίς βάση.
// Το τμήμα είναι κανονικό πεδίο του μοντέλου: κανένα singleton, καμία φόρτωση.
//
//   flutter test test/features/directory/similar_users_dialog_text_test.dart --timeout 30s

import 'package:call_logger/core/utils/user_similarity_finder.dart';
import 'package:call_logger/core/widgets/draggable_dialog_shell.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/screens/widgets/similar_users_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  SimilarUsersDialogResult? lastResult;

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<UserSimilarityMatch> matches,
    bool allowPickExisting = false,
    String typedDisplayName = 'Τυπωμένο Όνομα',
    String? typedDepartmentName,
    SimilarUsersDialogPurpose purpose =
        SimilarUsersDialogPurpose.directoryEntry,
  }) async {
    lastResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                lastResult = await showDialog<SimilarUsersDialogResult>(
                  context: context,
                  builder: (_) => SimilarUsersDialog(
                    matches: matches,
                    allowPickExisting: allowPickExisting,
                    typedDisplayName: typedDisplayName,
                    typedDepartmentName: typedDepartmentName,
                    purpose: purpose,
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

  testWidgets(
    'ταυτοπροσωπία — εμφανίζει αποθηκευμένο όνομα, τμήμα και τίτλο «Ίδιο ονοματεπώνυμο»',
    (tester) async {
      final user = UserModel(
        id: 1,
        firstName: 'Αναστασία',
        lastName: 'Φούφα',
        departmentId: 1,
        departmentName: 'Προσωπικού',
      );
      await pumpDialog(
        tester,
        matches: [
          UserSimilarityMatch(
            user: user,
            score: UserSimilarityFinder.kIdenticalScore,
          ),
        ],
      );

      expect(find.text('Ίδιο ονοματεπώνυμο'), findsOneWidget);
      expect(find.textContaining('Αναστασία Φούφα'), findsOneWidget);
      expect(find.textContaining('Προσωπικού'), findsOneWidget);
      expect(find.text('Συνέχεια ως Συνωνυμία'), findsOneWidget);
    },
  );

  testWidgets('δύο εγγραφές — εμφανίζονται και οι δύο γραμμές', (tester) async {
    await pumpDialog(
      tester,
      matches: [
        UserSimilarityMatch(
          user: UserModel(
            id: 1,
            firstName: 'Αναστασία',
            lastName: 'Αναστασιάδη',
            departmentId: 1,
            departmentName: 'Προσωπικού',
          ),
          score: UserSimilarityFinder.kIdenticalScore,
        ),
        UserSimilarityMatch(
          user: UserModel(
            id: 2,
            firstName: 'Αναστασία',
            lastName: 'Φούφα',
            departmentId: 2,
            departmentName: 'Προμηθειών',
          ),
          score: UserSimilarityFinder.kIdenticalScore,
        ),
      ],
    );

    expect(find.textContaining('Αναστασία Αναστασιάδη'), findsOneWidget);
    expect(find.textContaining('Αναστασία Φούφα'), findsOneWidget);
    expect(find.textContaining('Προσωπικού'), findsOneWidget);
    expect(find.textContaining('Προμηθειών'), findsOneWidget);
  });

  testWidgets('πρόταση — τίτλος «Μήπως εννοείτε;» και κουμπί νέας εγγραφής', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      matches: [
        UserSimilarityMatch(
          user: UserModel(
            id: 1,
            firstName: 'Βασίλης',
            lastName: 'Δρόσος',
            departmentId: 1,
            departmentName: 'Προσωπικού',
          ),
          score: 88,
        ),
      ],
    );

    expect(find.text('Μήπως εννοείτε;'), findsOneWidget);
    expect(find.text('Ίδιο ονοματεπώνυμο'), findsNothing);
    expect(find.text('Όχι, είναι νέα εγγραφή'), findsOneWidget);
    expect(find.text('Συνέχεια ως Συνωνυμία'), findsNothing);
  });

  testWidgets('καταγραφή κλήσης — καμία διατύπωση περί νέας εγγραφής', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      allowPickExisting: true,
      purpose: SimilarUsersDialogPurpose.callRecord,
      matches: [
        UserSimilarityMatch(
          user: UserModel(
            id: 1,
            firstName: 'Βασίλης',
            lastName: 'Δρόσος',
            departmentId: 1,
            departmentName: 'Προσωπικού',
          ),
          score: 95,
        ),
      ],
    );

    expect(find.text('Μήπως εννοείτε;'), findsOneWidget);
    expect(find.text('Όχι, κατέγραψε όπως το έγραψα'), findsOneWidget);
    expect(find.text('Όχι, είναι νέα εγγραφή'), findsNothing);
    expect(find.textContaining('νέα εγγραφή'), findsNothing);
    expect(find.textContaining('Βασίλης Δρόσος'), findsOneWidget);
  });

  testWidgets(
    'καταγραφή κλήσης — ταυτοπροσωπία δεν εμφανίζει αποτρεπτικό τίτλο',
    (tester) async {
      await pumpDialog(
        tester,
        allowPickExisting: true,
        purpose: SimilarUsersDialogPurpose.callRecord,
        matches: [
          UserSimilarityMatch(
            user: UserModel(
              id: 1,
              firstName: 'Βασίλης',
              lastName: 'Δρόσος',
              departmentId: 1,
              departmentName: 'Προσωπικού',
            ),
            score: UserSimilarityFinder.kIdenticalScore,
          ),
        ],
      );

      expect(find.text('Μήπως εννοείτε;'), findsOneWidget);
      expect(find.text('Ίδιο ονοματεπώνυμο'), findsNothing);
      expect(find.text('Συνέχεια ως Συνωνυμία'), findsNothing);
    },
  );

  testWidgets('μετονομασία — καμία διατύπωση περί νέας εγγραφής', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      purpose: SimilarUsersDialogPurpose.directoryRename,
      typedDisplayName: 'Θάνια Αναγνωστοπούλου',
      matches: [
        UserSimilarityMatch(
          user: UserModel(
            id: 1,
            firstName: 'Θάνια',
            lastName: 'Αναγνωστοπούλου',
            departmentId: 1,
            departmentName: 'Γραμματεία Κίνησης',
          ),
          score: UserSimilarityFinder.kIdenticalScore,
        ),
      ],
    );

    expect(find.text('Ναι, συνέχισε τη μετονομασία'), findsOneWidget);
    expect(
      find.textContaining('νέα εγγραφή'),
      findsNothing,
      reason: greekExpectMsg(
        'Η μετονομασία υπάρχουσας εγγραφής δεν δημιουργεί δεύτερη',
      ),
    );
    expect(find.text('Συνέχεια ως Συνωνυμία'), findsNothing);
    expect(find.textContaining('συνωνυμία'), findsNothing);
  });

  testWidgets(
    'σύγκριση — δείχνει τι πληκτρολογήθηκε και τι υπάρχει, με ετικέτες',
    (tester) async {
      await pumpDialog(
        tester,
        typedDisplayName: 'Βασίλης Δροσούλης',
        typedDepartmentName: '',
        matches: [
          UserSimilarityMatch(
            user: UserModel(
              id: 1,
              firstName: 'Βασίλης',
              lastName: 'Δρόσος',
              departmentId: 1,
              departmentName: 'Πληροφορική',
            ),
            score: 88,
          ),
        ],
      );

      expect(
        find.text('Πληκτρολογήσατε'),
        findsOneWidget,
        reason: greekExpectMsg('Ο διάλογος δείχνει τι πληκτρολόγησε ο χρήστης'),
      );
      expect(find.text('Υπάρχει ήδη'), findsOneWidget);
      expect(
        find.text('Βασίλης Δροσούλης', findRichText: true),
        findsOneWidget,
        reason: greekExpectMsg('Το πληκτρολογημένο όνομα εμφανίζεται'),
      );
      expect(find.text('Βασίλης Δρόσος', findRichText: true), findsOneWidget);
      expect(
        find.text('(χωρίς τμήμα)'),
        findsOneWidget,
        reason: greekExpectMsg(
          'Κενό τμήμα νέας εγγραφής δηλώνεται ρητά ως «(χωρίς τμήμα)»',
        ),
      );
      expect(find.text('(Πληροφορική)'), findsOneWidget);
    },
  );

  testWidgets('σύγκριση — ο διάλογος είναι μετακινήσιμος', (tester) async {
    await pumpDialog(
      tester,
      typedDisplayName: 'Βασίλης Δροσούλης',
      matches: [
        UserSimilarityMatch(
          user: UserModel(id: 1, firstName: 'Βασίλης', lastName: 'Δρόσος'),
          score: 88,
        ),
      ],
    );

    expect(
      find.byType(DraggableDialogShell),
      findsOneWidget,
      reason: greekExpectMsg(
        'Ο διάλογος «Μήπως εννοείτε;» πρέπει να μετακινείται για να '
        'φαίνεται η φόρμα από πίσω',
      ),
    );
  });

  testWidgets(
    'σύγκριση — πάτημα σε υπάρχοντα επιστρέφει επιλογή όταν επιτρέπεται',
    (tester) async {
      final existing = UserModel(
        id: 7,
        firstName: 'Βασίλης',
        lastName: 'Δρόσος',
        departmentId: 1,
        departmentName: 'Πληροφορική',
      );
      await pumpDialog(
        tester,
        allowPickExisting: true,
        typedDisplayName: 'Βασίλης Δροσούλης',
        matches: [UserSimilarityMatch(user: existing, score: 88)],
      );

      await tester.tap(find.text('Βασίλης Δρόσος', findRichText: true));
      await tester.pumpAndSettle();

      expect(
        lastResult?.selectedUser?.id,
        7,
        reason: greekExpectMsg(
          'Το πάτημα στη γραμμή του υπάρχοντος επιστρέφει τον χρήστη',
        ),
      );
    },
  );
}
