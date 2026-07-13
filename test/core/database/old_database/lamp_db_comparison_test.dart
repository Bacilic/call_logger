import 'package:call_logger/core/database/old_database/lamp_db_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLampDbComparisonNotifications', () {
    test('ίδιο αρχείο δεν παράγει ειδοποιήσεις', () {
      final snapshot = LampDbSnapshot(
        exists: true,
        modified: DateTime(2026, 7, 1, 10),
        equipmentCount: 100,
        issuesCount: 5,
      );
      final notifications = buildLampDbComparisonNotifications(
        read: snapshot,
        output: snapshot,
        readPath: r'C:\Data\lamp.db',
        outputPath: r'c:\data\lamp.db',
      );
      expect(notifications, isEmpty);
    });

    test('πιο πρόσφατη έξοδος', () {
      final notifications = buildLampDbComparisonNotifications(
        read: LampDbSnapshot(
          exists: true,
          modified: DateTime(2026, 7, 1, 10),
          equipmentCount: 100,
          issuesCount: 5,
        ),
        output: LampDbSnapshot(
          exists: true,
          modified: DateTime(2026, 7, 2, 12),
          equipmentCount: 100,
          issuesCount: 5,
        ),
        readPath: r'C:\read.db',
        outputPath: r'C:\out.db',
      );
      expect(
        notifications.any((line) => line.contains('πιο πρόσφατη')),
        isTrue,
      );
    });

    test('διαφορά πλήθους εξοπλισμού με αμφότερους αριθμούς', () {
      final notifications = buildLampDbComparisonNotifications(
        read: const LampDbSnapshot(
          exists: true,
          equipmentCount: 3488,
          issuesCount: 0,
        ),
        output: const LampDbSnapshot(
          exists: true,
          equipmentCount: 3818,
          issuesCount: 0,
        ),
        readPath: r'C:\read.db',
        outputPath: r'C:\out.db',
      );
      expect(
        notifications,
        contains(
          'Διαφορά στο πλήθος εξοπλισμού: ανάγνωση 3488, έξοδος 3818.',
        ),
      );
    });

    test('διαφορά πλήθους προβλημάτων', () {
      final notifications = buildLampDbComparisonNotifications(
        read: const LampDbSnapshot(
          exists: true,
          equipmentCount: 10,
          issuesCount: 2,
        ),
        output: const LampDbSnapshot(
          exists: true,
          equipmentCount: 10,
          issuesCount: 7,
        ),
        readPath: r'C:\read.db',
        outputPath: r'C:\out.db',
      );
      expect(
        notifications,
        contains(
          'Διαφορά στο πλήθος προβλημάτων (data_issues): ανάγνωση 2, έξοδος 7.',
        ),
      );
    });

    test('λείπει η ανάγνωση ενώ υπάρχει έξοδος', () {
      final notifications = buildLampDbComparisonNotifications(
        read: const LampDbSnapshot(exists: false),
        output: const LampDbSnapshot(
          exists: true,
          equipmentCount: 100,
          issuesCount: 1,
        ),
        readPath: '',
        outputPath: r'C:\out.db',
      );
      expect(
        notifications,
        contains(
          'Δεν έχει οριστεί ή δεν βρέθηκε η βάση ανάγνωσης, ενώ υπάρχει φρέσκια βάση εξόδου.',
        ),
      );
    });
  });
}
