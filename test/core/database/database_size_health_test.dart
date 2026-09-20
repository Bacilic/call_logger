// Πότε η βάση αξίζει προσοχή, και πόσο καιρό έχει ως εκεί.
//
// Τα κατώφλια δεν βγαίνουν από την τεκμηρίωση της SQLite — εκείνη λέει
// 281 terabyte, δηλαδή τίποτα που να μας αφορά. Βγαίνουν από τον χρόνο που
// περιμένει ο χειριστής σε κάθε αντίγραφο, γιατί το αντίγραφο διαβάζει
// ολόκληρο το αρχείο πάνω από το δίκτυο.
//
//   flutter test test/core/database/database_size_health_test.dart

import 'package:call_logger/core/database/database_size_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 19);
  const mb = 1024 * 1024;

  group('επίπεδο μεγέθους', () {
    test('μικρή βάση δεν χρειάζεται τίποτα', () {
      final v = judgeDatabaseSize(
        sizeBytes: 13 * mb,
        oldestRecordAt: null,
        now: now,
      );
      expect(v.level, DatabaseSizeLevel.comfortable);
    });

    test('στο κατώφλι των 50 MB μπαίνει σε επιφυλακή', () {
      final v = judgeDatabaseSize(
        sizeBytes: kDatabaseSizeWatchBytes,
        oldestRecordAt: null,
        now: now,
      );
      expect(v.level, DatabaseSizeLevel.watch);
    });

    test('ένα byte κάτω από το κατώφλι μένει ήσυχη', () {
      final v = judgeDatabaseSize(
        sizeBytes: kDatabaseSizeWatchBytes - 1,
        oldestRecordAt: null,
        now: now,
      );
      expect(v.level, DatabaseSizeLevel.comfortable);
    });

    test('στα 200 MB το αντίγραφο κοστίζει αισθητά', () {
      final v = judgeDatabaseSize(
        sizeBytes: kDatabaseSizeCrowdedBytes,
        oldestRecordAt: null,
        now: now,
      );
      expect(v.level, DatabaseSizeLevel.crowded);
      expect(v.nextLevelBytes, isNull, reason: 'δεν υπάρχει επόμενο επίπεδο');
    });

    test('ο χρόνος αντιγράφου αντιστοιχεί στα κατώφλια', () {
      final watch = judgeDatabaseSize(
        sizeBytes: kDatabaseSizeWatchBytes,
        oldestRecordAt: null,
        now: now,
      );
      final crowded = judgeDatabaseSize(
        sizeBytes: kDatabaseSizeCrowdedBytes,
        oldestRecordAt: null,
        now: now,
      );

      // Τα κατώφλια επιλέχθηκαν ώστε να σημαίνουν «λίγα δευτερόλεπτα» και
      // «πάνω από ένα τέταρτο του λεπτού» σε αργό δίκτυο.
      expect(watch.backupSecondsOnSlowNetwork, closeTo(4.5, 0.5));
      expect(crowded.backupSecondsOnSlowNetwork, closeTo(18.2, 0.5));
    });
  });

  group('εκτίμηση ρυθμού', () {
    test('η πραγματική βάση του νοσοκομείου φτάνει σε χρόνια, όχι μήνες', () {
      // Μετρημένο 19/09: 12,8 MB, πρώτη εγγραφή Ιστορικού 05/06 του ίδιου
      // έτους — δηλαδή 106 ημέρες ζωής.
      final v = judgeDatabaseSize(
        sizeBytes: (12.8 * mb).round(),
        oldestRecordAt: DateTime(2026, 6, 5),
        now: now,
      );

      expect(v.level, DatabaseSizeLevel.comfortable);
      expect(v.bytesPerDay, isNotNull);
      expect(
        v.daysUntilNextLevel,
        greaterThan(300),
        reason: 'ως τα 50 MB έχει πάνω από έναν χρόνο',
      );
    });

    test('χωρίς ιστορία δεν βγαίνει εκτίμηση', () {
      final v = judgeDatabaseSize(
        sizeBytes: 20 * mb,
        oldestRecordAt: null,
        now: now,
      );
      expect(v.bytesPerDay, isNull);
      expect(v.daysUntilNextLevel, isNull);
    });

    test('ολοκαίνουργια βάση δεν βγάζει ρυθμό από τρεις μέρες', () {
      // Τρεις μέρες μετά την εγκατάσταση, ο «ρυθμός» θα ήταν θόρυβος.
      final v = judgeDatabaseSize(
        sizeBytes: 8 * mb,
        oldestRecordAt: now.subtract(const Duration(days: 3)),
        now: now,
      );
      expect(v.bytesPerDay, isNull);
      expect(v.daysUntilNextLevel, isNull);
    });

    test('γρήγορος ρυθμός δίνει κοντινή προθεσμία', () {
      // 40 MB σε 20 μέρες = 2 MB/μέρα → 5 μέρες ως τα 50 MB.
      final v = judgeDatabaseSize(
        sizeBytes: 40 * mb,
        oldestRecordAt: now.subtract(const Duration(days: 20)),
        now: now,
      );
      expect(v.daysUntilNextLevel, 5);
    });

    test('στο τελευταίο επίπεδο δεν υπάρχει προθεσμία', () {
      final v = judgeDatabaseSize(
        sizeBytes: 250 * mb,
        oldestRecordAt: now.subtract(const Duration(days: 500)),
        now: now,
      );
      expect(v.level, DatabaseSizeLevel.crowded);
      expect(v.daysUntilNextLevel, isNull);
    });
  });

  group('διατύπωση χρόνου', () {
    test('μέρες, μήνες και χρόνια κατά περίπτωση', () {
      expect(formatDaysAhead(20), 'σε 20 μέρες');
      expect(formatDaysAhead(60), 'σε 2 μήνες');
      expect(formatDaysAhead(30), 'σε 30 μέρες');
      expect(formatDaysAhead(1522), 'σε 4 χρόνια περίπου');
      expect(formatDaysAhead(0), 'τώρα');
      expect(formatDaysAhead(5000), 'σε πάνω από 10 χρόνια');
    });

    test('ένας μήνας και ένας χρόνος γράφονται στον ενικό', () {
      expect(formatDaysAhead(32), 'σε 32 μέρες');
      expect(formatDaysAhead(45), 'σε 2 μήνες');
      expect(formatDaysAhead(400), 'σε έναν χρόνο περίπου');
    });
  });

  group('συμβουλή', () {
    test('κάθε επίπεδο λέει κάτι διαφορετικό', () {
      final all = DatabaseSizeLevel.values.map(databaseSizeAdvice).toSet();
      expect(all.length, DatabaseSizeLevel.values.length);
    });

    test('καμία συμβουλή δεν είναι προσταγή', () {
      for (final level in DatabaseSizeLevel.values) {
        expect(databaseSizeAdvice(level), isNot(contains('πρέπει')));
      }
    });
  });
}
