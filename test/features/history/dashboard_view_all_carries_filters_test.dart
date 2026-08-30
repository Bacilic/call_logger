// Το «Προβολή όλων» οδηγεί σε ό,τι έδειχνε η κάρτα.
//
// Ο χρήστης φιλτράρει τα Στατιστικά στο τμήμα «Αιματολογικό», πατά «Προβολή
// όλων» και το Ιστορικό άνοιγε με ΟΛΕΣ τις κλήσεις όλων των τμημάτων: ίδιο
// χρονικό διάστημα, άλλο σύνολο από αυτό που κοίταζε.
//
//   flutter test test/features/history/dashboard_view_all_carries_filters_test.dart

import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  final dashboard = DashboardFilterModel(
    dateFrom: DateTime(2026, 6, 17),
    dateTo: DateTime(2026, 7, 22),
    department: 'Αιματολογικό',
    userName: 'Ψαρρά',
    equipmentCode: '5010',
  );

  group('Μετάβαση από τα Στατιστικά στο Ιστορικό', () {
    test('μεταφέρονται τμήμα, υπάλληλος και εξοπλισμός', () {
      final container = makeContainer();

      container
          .read(historyFilterProvider.notifier)
          .focusFromDashboard(dashboard);

      final history = container.read(historyFilterProvider);
      expect(history.department, 'Αιματολογικό');
      expect(history.userName, 'Ψαρρά');
      expect(history.equipmentCode, '5010');
    });

    test('μεταφέρεται και το χρονικό διάστημα', () {
      final container = makeContainer();

      container
          .read(historyFilterProvider.notifier)
          .focusFromDashboard(dashboard);

      final history = container.read(historyFilterProvider);
      expect(history.dateFrom, DateTime(2026, 6, 17));
      expect(history.dateTo, DateTime(2026, 7, 22));
    });

    test('παλιά φίλτρα του Ιστορικού που δεν μεταφέρονται καθαρίζονται', () {
      final container = makeContainer();
      container
          .read(historyFilterProvider.notifier)
          .update((s) => s.copyWith(category: 'Εκτυπωτές', onlyWithTask: true));

      final cleared = container
          .read(historyFilterProvider.notifier)
          .focusFromDashboard(dashboard);

      expect(container.read(historyFilterProvider).category, isNull);
      expect(cleared, containsAll(<String>['κατηγορία', 'με εκκρεμότητα']));
    });

    test('τα φίλτρα που ΗΡΘΑΝ δεν αναφέρονται ως χαμένα', () {
      final container = makeContainer();
      container
          .read(historyFilterProvider.notifier)
          .update((s) => s.copyWith(department: 'Γραφείο Κίνησης'));

      final cleared = container
          .read(historyFilterProvider.notifier)
          .focusFromDashboard(dashboard);

      expect(
        cleared,
        isNot(contains('τμήμα')),
        reason:
            'Το τμήμα δεν χάθηκε — αντικαταστάθηκε από αυτό της κάρτας. Το '
            'μήνυμα θα έλεγε ψέματα.',
      );
    });

    test(
      'άδειος Πίνακας Ελέγχου αφήνει το Ιστορικό χωρίς φίλτρα οντότητας',
      () {
        final container = makeContainer();

        container
            .read(historyFilterProvider.notifier)
            .focusFromDashboard(const DashboardFilterModel());

        final history = container.read(historyFilterProvider);
        expect(history.department, isNull);
        expect(history.userName, isNull);
        expect(history.equipmentCode, isNull);
      },
    );
  });
}
