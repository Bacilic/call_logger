// Κείμενο διαλόγου παρόμοιων υπαλλήλων — σκέτα UserModel, χωρίς βάση.
// Το τμήμα είναι κανονικό πεδίο του μοντέλου: κανένα singleton, καμία φόρτωση.
//
//   flutter test test/features/directory/similar_users_dialog_text_test.dart --timeout 30s

import 'package:call_logger/core/utils/user_similarity_finder.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/screens/widgets/similar_users_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<UserSimilarityMatch> matches,
    bool allowPickExisting = false,
    SimilarUsersDialogPurpose purpose =
        SimilarUsersDialogPurpose.directoryEntry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<SimilarUsersDialogResult>(
                  context: context,
                  builder: (_) => SimilarUsersDialog(
                    matches: matches,
                    allowPickExisting: allowPickExisting,
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
}
