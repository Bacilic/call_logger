// Μετάβαση στο Ιστορικό από άλλη οθόνη: το πλαίσιο ορίζεται ολόκληρο και ο
// χρήστης μαθαίνει ποια φίλτρα έπαψαν να ισχύουν.
//
//   flutter test test/features/history/history_filter_focus_test.dart

import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/features/history/utils/history_navigation_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('activeFilterLabels', () {
    test('χωρίς φίλτρα η λίστα είναι κενή', () {
      expect(const HistoryFilterModel().activeFilterLabels, isEmpty);
    });

    test('ονομάζει κάθε ενεργό φίλτρο', () {
      final filter = HistoryFilterModel(
        keyword: '5067',
        dateFrom: DateTime(2026, 7),
        category: 'Medico',
        onlyWithTask: true,
        lansweeperState: LansweeperSyncState.excluded,
      );

      expect(filter.activeFilterLabels, [
        'αναζήτηση',
        'ημερομηνίες',
        'κατηγορία',
        'με εκκρεμότητα',
        'Lansweeper: Εξαιρεμένες',
      ]);
    });

    test('κενή αναζήτηση και κενή κατηγορία δεν μετρούν ως φίλτρα', () {
      const filter = HistoryFilterModel(keyword: '   ', category: '  ');

      expect(filter.activeFilterLabels, isEmpty);
    });

    test('το φίλτρο κατάστασης ονομάζει ποια κατάσταση δείχνει', () {
      // Η ετικέτα δεν λέει σκέτο «Lansweeper»: ο χρήστης που επιστρέφει στην
      // οθόνη πρέπει να μαθαίνει ποιο υποσύνολο βλέπει, όχι μόνο ότι φιλτράρει.
      const unsent = HistoryFilterModel(
        lansweeperState: LansweeperSyncState.unsent,
      );
      const sent = HistoryFilterModel(
        lansweeperState: LansweeperSyncState.sent,
      );

      expect(unsent.activeFilterLabels, ['Lansweeper: Ακαταχώρητες']);
      expect(sent.activeFilterLabels, ['Lansweeper: Καταχωρημένες']);
    });

    test('κενή κατάσταση δεν μετράει ως φίλτρο', () {
      const filter = HistoryFilterModel(lansweeperState: '  ');

      expect(filter.activeFilterLabels, isEmpty);
      expect(filter.hasActiveFilters, isFalse);
    });
  });

  group('HistoryFilterNotifier.focus', () {
    ProviderContainer buildContainer() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container;
    }

    test('μηδενίζει ό,τι δεν ζητήθηκε ρητά', () {
      final container = buildContainer();
      container
          .read(historyFilterProvider.notifier)
          .update(
            (s) => s.copyWith(
              category: 'Medico',
              dateFrom: DateTime(2026, 7),
              dateTo: DateTime(2026, 7, 31),
              onlyWithTask: true,
              lansweeperState: LansweeperSyncState.sent,
            ),
          );

      container.read(historyFilterProvider.notifier).focus(keyword: '5067');

      final filter = container.read(historyFilterProvider);
      expect(filter.keyword, '5067');
      expect(filter.category, isNull);
      expect(filter.dateFrom, isNull);
      expect(filter.dateTo, isNull);
      expect(filter.onlyWithTask, isFalse);
      expect(filter.lansweeperState, isNull);
    });

    test('το φίλτρο κατάστασης καθαρίζεται ρητά, χωρίς να χρειάζεται νέα τιμή', () {
      final container = buildContainer();
      container
          .read(historyFilterProvider.notifier)
          .update((s) => s.copyWith(lansweeperState: LansweeperSyncState.sent));

      container
          .read(historyFilterProvider.notifier)
          .update((s) => s.copyWith(clearLansweeperState: true));

      expect(container.read(historyFilterProvider).lansweeperState, isNull);
    });

    test('επιστρέφει τα φίλτρα που έπαψαν να ισχύουν', () {
      final container = buildContainer();
      container
          .read(historyFilterProvider.notifier)
          .update(
            (s) => s.copyWith(
              category: 'Medico',
              lansweeperState: LansweeperSyncState.excluded,
            ),
          );

      final cleared = container
          .read(historyFilterProvider.notifier)
          .focus(keyword: '5067');

      expect(cleared, ['κατηγορία', 'Lansweeper: Εξαιρεμένες']);
    });

    test('φίλτρο που αντικαταστάθηκε δεν μετράει ως καθαρισμένο', () {
      final container = buildContainer();
      container
          .read(historyFilterProvider.notifier)
          .update(
            (s) => s.copyWith(
              dateFrom: DateTime(2026, 7),
              dateTo: DateTime(2026, 7, 31),
              category: 'Medico',
            ),
          );

      final cleared = container
          .read(historyFilterProvider.notifier)
          .focus(dateFrom: DateTime(2026, 8), dateTo: DateTime(2026, 8, 31));

      expect(cleared, ['κατηγορία']);
      expect(container.read(historyFilterProvider).dateFrom, DateTime(2026, 8));
    });

    test('χωρίς προηγούμενα φίλτρα δεν καθαρίζεται τίποτα', () {
      final container = buildContainer();

      final cleared = container
          .read(historyFilterProvider.notifier)
          .focus(keyword: '5067');

      expect(cleared, isEmpty);
    });
  });

  group('historyFiltersClearedMessage', () {
    test('κενή λίστα δεν παράγει μήνυμα', () {
      expect(historyFiltersClearedMessage(const []), isNull);
    });

    test('ένα φίλτρο στον ενικό', () {
      expect(
        historyFiltersClearedMessage(const ['κατηγορία']),
        'Καθαρίστηκε το φίλτρο: κατηγορία.',
      );
    });

    test('περισσότερα στον πληθυντικό, χωρισμένα με κόμμα', () {
      expect(
        historyFiltersClearedMessage(const ['κατηγορία', 'ημερομηνίες']),
        'Καθαρίστηκαν τα φίλτρα: κατηγορία, ημερομηνίες.',
      );
    });
  });

  group('showHistoryFiltersClearedSnackBar', () {
    Future<ScaffoldMessengerState> pumpHost(WidgetTester tester) async {
      late ScaffoldMessengerState messenger;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                messenger = ScaffoldMessenger.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return messenger;
    }

    testWidgets('εμφανίζει το μήνυμα όταν καθαρίστηκαν φίλτρα', (tester) async {
      final messenger = await pumpHost(tester);

      showHistoryFiltersClearedSnackBar(messenger, const ['κατηγορία']);
      await tester.pump();

      expect(find.text('Καθαρίστηκε το φίλτρο: κατηγορία.'), findsOneWidget);
    });

    testWidgets('δεν εμφανίζει τίποτα όταν δεν καθαρίστηκε τίποτα', (
      tester,
    ) async {
      final messenger = await pumpHost(tester);

      showHistoryFiltersClearedSnackBar(messenger, const []);
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
