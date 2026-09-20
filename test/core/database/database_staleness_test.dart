// Πότε μια βάση θεωρείται στάσιμη — και πότε η σιωπή είναι η σωστή απάντηση.
//
// Το επεισόδιο 17/07/2026: ένα τμήμα «χάθηκε» ενώ ο χρήστης δούλευε πάνω σε
// παλαιότερο αντίγραφο. Αυτό που έλυσε τη διάγνωση ήταν η τελευταία εγγραφή
// Ιστορικού, δέκα μέρες πίσω — όχι η ημερομηνία του αρχείου, που έδειχνε
// χθεσινή επειδή το αρχείο είχε μετακινηθεί.
//
//   flutter test test/core/database/database_staleness_test.dart

import 'package:call_logger/core/database/database_staleness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 19, 10, 0);

  group('κρίση στασιμότητας', () {
    test('βάση που γράφτηκε σήμερα δεν είναι στάσιμη', () {
      final verdict = judgeDatabaseStaleness(
        lastChangeAt: now.subtract(const Duration(hours: 3)),
        thresholdDays: 5,
        now: now,
      );

      expect(verdict.isStale, isFalse);
      expect(verdict.daysSinceLastChange, 0);
    });

    test('βάση πέρα από το όριο είναι στάσιμη', () {
      final verdict = judgeDatabaseStaleness(
        lastChangeAt: now.subtract(const Duration(days: 10)),
        thresholdDays: 5,
        now: now,
      );

      expect(verdict.isStale, isTrue);
      expect(verdict.daysSinceLastChange, 10);
      expect(verdict.thresholdDays, 5);
    });

    test('ακριβώς στο όριο μετρά ως στάσιμη', () {
      final verdict = judgeDatabaseStaleness(
        lastChangeAt: now.subtract(const Duration(days: 5)),
        thresholdDays: 5,
        now: now,
      );

      expect(verdict.isStale, isTrue);
    });

    test('μία μέρα πριν από το όριο δεν είναι στάσιμη', () {
      final verdict = judgeDatabaseStaleness(
        lastChangeAt: now.subtract(const Duration(days: 4, hours: 23)),
        thresholdDays: 5,
        now: now,
      );

      expect(verdict.isStale, isFalse);
    });

    test('κενή βάση δεν προειδοποιεί ποτέ', () {
      final verdict = judgeDatabaseStaleness(
        lastChangeAt: null,
        thresholdDays: 1,
        now: now,
      );

      expect(verdict.isStale, isFalse);
      expect(verdict.lastChangeAt, isNull);
      expect(verdict.daysSinceLastChange, isNull);
    });

    test('ημερομηνία στο μέλλον δεν βγάζει αρνητικές μέρες', () {
      final verdict = judgeDatabaseStaleness(
        lastChangeAt: now.add(const Duration(days: 2)),
        thresholdDays: 5,
        now: now,
      );

      expect(verdict.isStale, isFalse);
      expect(verdict.daysSinceLastChange, 0);
    });

    test('το όριο που ταξιδεύει στην ετυμηγορία είναι το κανονικοποιημένο', () {
      final verdict = judgeDatabaseStaleness(
        lastChangeAt: now.subtract(const Duration(days: 400)),
        thresholdDays: 9999,
        now: now,
      );

      expect(verdict.thresholdDays, kMaxDatabaseStalenessDays);
      expect(verdict.isStale, isTrue);
    });
  });

  group('κανονικοποίηση ορίου', () {
    test('η απουσία τιμής δίνει την προεπιλογή', () {
      expect(
        normalizeDatabaseStalenessDays(null),
        kDefaultDatabaseStalenessDays,
      );
    });

    test('τιμές εκτός ορίων μαζεύονται μέσα', () {
      expect(normalizeDatabaseStalenessDays(0), kMinDatabaseStalenessDays);
      expect(normalizeDatabaseStalenessDays(-7), kMinDatabaseStalenessDays);
      expect(normalizeDatabaseStalenessDays(900), kMaxDatabaseStalenessDays);
    });

    test('έγκυρη τιμή περνά ανέπαφη', () {
      expect(normalizeDatabaseStalenessDays(12), 12);
    });
  });
}
