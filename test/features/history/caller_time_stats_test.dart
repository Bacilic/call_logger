// Όψη «χρόνος ανά άτομο»: ταξινόμηση, μέσος όρος, απόκρυψη «Άγνωστου».
//
//   flutter test test/features/history/caller_time_stats_test.dart

import 'package:call_logger/features/history/models/dashboard_summary_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

CallerTimeStat _stat(String name, int calls, int totalSeconds) =>
    CallerTimeStat(
      name: name,
      callCount: calls,
      totalDurationSeconds: totalSeconds,
    );

void main() {
  // Πραγματικά δεδομένα 30/07: η Νάντια έχει τις λιγότερες κλήσεις αλλά τον
  // περισσότερο χρόνο· η Φιλιώ το αντίστροφο.
  final nadia = _stat('Νάντια Χατζοπούλου', 3, 14278);
  final filio = _stat('Φιλιώ Γκίλλα', 9, 2636);
  final anastasia = _stat('Αναστασία Αναστασιάδη', 6, 4344);
  final unknown = _stat(kDashboardUnknownCallerLabel, 78, 33960);

  group('CallerTimeStat.avgDurationSeconds', () {
    test('μέσος όρος ανά κλήση', () {
      expect(nadia.avgDurationSeconds, 4759);
      expect(filio.avgDurationSeconds, 293);
    });

    test('χωρίς κλήσεις δεν διαιρεί με το μηδέν', () {
      expect(_stat('Κανείς', 0, 0).avgDurationSeconds, 0);
    });
  });

  group('sortedCallerTimeStats', () {
    final stats = [filio, nadia, anastasia];

    test('κατά σύνολο — λίγες μεγάλες κλήσεις νικούν πολλές σύντομες', () {
      final sorted = sortedCallerTimeStats(stats, CallerTimeSort.total);
      expect(
        sorted.map((s) => s.name).toList(),
        ['Νάντια Χατζοπούλου', 'Αναστασία Αναστασιάδη', 'Φιλιώ Γκίλλα'],
        reason: greekExpectMsg(
          'Η Νάντια με 3 κλήσεις προηγείται της Φιλιώς με 9',
        ),
      );
    });

    test('κατά πλήθος — αντιστρέφεται η εικόνα', () {
      final sorted = sortedCallerTimeStats(stats, CallerTimeSort.count);
      expect(sorted.first.name, 'Φιλιώ Γκίλλα');
    });

    test('κατά μέσο όρο', () {
      final sorted = sortedCallerTimeStats(stats, CallerTimeSort.average);
      expect(sorted.map((s) => s.name).first, 'Νάντια Χατζοπούλου');
      expect(sorted.map((s) => s.name).last, 'Φιλιώ Γκίλλα');
    });

    test('ισοπαλία σπάει με το όνομα, ώστε η σειρά να μην αλλάζει τυχαία', () {
      final tied = [_stat('Βήτα', 2, 600), _stat('Άλφα', 2, 600)];
      expect(
        sortedCallerTimeStats(tied, CallerTimeSort.total).first.name,
        'Άλφα',
      );
    });

    test('δεν πειράζει την αρχική λίστα', () {
      final original = [filio, nadia];
      sortedCallerTimeStats(original, CallerTimeSort.total);
      expect(original.first.name, 'Φιλιώ Γκίλλα');
    });
  });

  group('visibleCallerTimeStats — διακόπτης «Άγνωστου»', () {
    final stats = [unknown, nadia, filio];

    test('κλειστός διακόπτης: εμφανίζονται όλοι', () {
      expect(
        visibleCallerTimeStats(stats, hideUnknownCaller: false),
        hasLength(3),
      );
    });

    test('ανοιχτός διακόπτης: φεύγει μόνο ο «Άγνωστος»', () {
      final visible = visibleCallerTimeStats(stats, hideUnknownCaller: true);
      expect(visible, hasLength(2));
      expect(
        visible.any((s) => s.name == kDashboardUnknownCallerLabel),
        isFalse,
        reason: greekExpectMsg(
          'Ο «Άγνωστος» δεν είναι πρόσωπο — κρύβεται για να φαίνονται οι '
          'πραγματικοί άνθρωποι',
        ),
      );
      expect(visible.map((s) => s.name), contains('Νάντια Χατζοπούλου'));
    });
  });
}
