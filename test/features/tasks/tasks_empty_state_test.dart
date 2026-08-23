// Η άδεια οθόνη των Εκκρεμοτήτων λέει ΓΙΑΤΙ είναι άδεια.
//
// Ο μετρητής της πλοήγησης δεν ακολουθεί το φίλτρο χρήστη — είναι ειδοποίηση,
// και ένα φίλτρο προβολής δεν επιτρέπεται να κρύψει δουλειά που υπάρχει. Η
// αντίφαση «μετρητής 1, οθόνη άδεια» λύνεται εδώ, με λόγια και με διέξοδο.
//
//   flutter test test/features/tasks/tasks_empty_state_test.dart

import 'package:call_logger/core/models/owner_filter.dart';
import 'package:call_logger/features/tasks/providers/task_owner_filter_provider.dart';
import 'package:call_logger/features/tasks/screens/tasks_screen_support_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Καταγράφει τι ζητήθηκε να γίνει το φίλτρο, χωρίς να αγγίξει βάση.
class _RecordingOwnerNotifier extends TaskOwnerFilterNotifier {
  _RecordingOwnerNotifier(this.initial);

  final OwnerFilter initial;
  final List<OwnerFilter> selections = [];

  @override
  Future<OwnerFilter> build() async => initial;

  @override
  Future<void> select(OwnerFilter owner) async {
    selections.add(owner);
    state = AsyncValue.data(owner);
  }
}

void main() {
  late _RecordingOwnerNotifier ownerNotifier;

  Future<void> pumpEmptyState(
    WidgetTester tester, {
    required int totalTaskCount,
    required int hidden,
    OwnerFilter owner = const OwnerFilter.byOperator(11),
  }) async {
    ownerNotifier = _RecordingOwnerNotifier(owner);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskOwnerFilterProvider.overrideWith(() => ownerNotifier),
          tasksHiddenByOwnerFilterProvider.overrideWith((ref) async => hidden),
          taskOwnerOptionsProvider.overrideWith(
            (ref) async => const [
              OwnerFilterOption(value: OwnerFilter.everyone, label: 'Όλοι'),
              OwnerFilterOption(
                value: OwnerFilter.byOperator(11),
                label: 'Bacilic',
              ),
              OwnerFilterOption(
                value: OwnerFilter.unassigned,
                label: 'Χωρίς χρήστη',
              ),
            ],
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: TasksEmptyState(totalTaskCount: totalTaskCount)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Άδεια οθόνη Εκκρεμοτήτων', () {
    testWidgets('χωρίς καμία εκκρεμότητα, το λέει απλά', (tester) async {
      await pumpEmptyState(tester, totalTaskCount: 0, hidden: 0);

      expect(
        find.text('Δεν υπάρχουν εκκρεμότητες αυτή τη στιγμή'),
        findsOneWidget,
      );
      expect(find.text('Δείξε όλες'), findsNothing);
    });

    testWidgets('όταν φταίνε άλλα φίλτρα, δεν κατηγορεί τον χρήστη', (
      tester,
    ) async {
      await pumpEmptyState(tester, totalTaskCount: 5, hidden: 0);

      expect(
        find.text('Δεν βρέθηκαν εκκρεμότητες με τα επιλεγμένα κριτήρια'),
        findsOneWidget,
      );
      expect(
        find.text('Δείξε όλες'),
        findsNothing,
        reason:
            'Διέξοδος που δεν οδηγεί πουθενά είναι χειρότερη από καθόλου: το '
            'φίλτρο χρήστη δεν κρύβει τίποτα εδώ.',
      );
    });

    testWidgets('όταν κρύβει το φίλτρο χρήστη, το εξηγεί ονομαστικά', (
      tester,
    ) async {
      await pumpEmptyState(tester, totalTaskCount: 5, hidden: 1);

      expect(find.text('Καμία εκκρεμότητα για «Bacilic»'), findsOneWidget);
      expect(find.text('Υπάρχει 1 ακόμη με άλλον χρήστη.'), findsOneWidget);
      expect(find.text('Δείξε όλες'), findsOneWidget);
    });

    testWidgets('στον πληθυντικό μετράει σωστά', (tester) async {
      await pumpEmptyState(tester, totalTaskCount: 9, hidden: 4);

      expect(find.text('Υπάρχουν 4 ακόμη με άλλον χρήστη.'), findsOneWidget);
    });

    testWidgets('το όνομα ακολουθεί την πραγματική επιλογή', (tester) async {
      await pumpEmptyState(
        tester,
        totalTaskCount: 5,
        hidden: 2,
        owner: OwnerFilter.unassigned,
      );

      expect(find.text('Καμία εκκρεμότητα για «Χωρίς χρήστη»'), findsOneWidget);
    });

    testWidgets('το «Δείξε όλες» γυρίζει το φίλτρο σε «Όλοι»', (tester) async {
      await pumpEmptyState(tester, totalTaskCount: 5, hidden: 1);

      await tester.tap(find.text('Δείξε όλες'));
      await tester.pumpAndSettle();

      expect(ownerNotifier.selections, [OwnerFilter.everyone]);
    });

    testWidgets('με φίλτρο «Όλοι» δεν προσφέρεται διέξοδος', (tester) async {
      await pumpEmptyState(
        tester,
        totalTaskCount: 5,
        hidden: 3,
        owner: OwnerFilter.everyone,
      );

      expect(
        find.text('Δείξε όλες'),
        findsNothing,
        reason: 'Το φίλτρο δείχνει ήδη όλες — δεν υπάρχει πού να πάει.',
      );
    });
  });
}
