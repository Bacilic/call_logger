// Κατάσταση αυτόματων αντιγράφων για το UI (Φάση 3: μετρητής αλλαγών).
// Ελέγχεται η υπόσχεση των κειμένων — τι λέει η οθόνη και πότε — όχι η
// απόφαση πυροδότησης (εκείνη ζει στο backup_trigger_decision_test.dart).
//
//   flutter test test/features/database/utils/backup_schedule_status_test.dart

import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/utils/backup_destination_folder_validator.dart';
import 'package:call_logger/features/database/utils/backup_schedule_status.dart';
import 'package:call_logger/features/database/utils/backup_schedule_utils.dart';
import 'package:flutter_test/flutter_test.dart';

DatabaseBackupSettings _settings({
  String destination = r'C:\Backups',
  bool enabled = true,
  int threshold = 100,
  int minSpacing = 15,
  int maxWait = 240,
  DateTime? lastAttempt,
  DateTime? lastManual,
  String lastStatus = BackupScheduleStatus.none,
}) => DatabaseBackupSettings.defaults().copyWith(
  destinationDirectory: destination,
  backupOnExit: enabled,
  changeThreshold: threshold,
  minSpacingMinutes: minSpacing,
  maxWaitMinutes: maxWait,
  lastBackupAttempt: lastAttempt,
  lastManualBackupAttempt: lastManual,
  lastBackupStatus: lastStatus,
);

void main() {
  final now = DateTime(2026, 8, 24, 12, 0);

  group('build — κατάσταση μετρητή', () {
    test('απενεργοποιημένα: μόνο η υπόδειξη, καμία πρόβλεψη', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(enabled: false),
        pendingChanges: 50,
        now: now,
      );
      expect(info.hintText, contains('απενεργοποιημένα'));
      expect(info.nextBackupText, isNull);
    });

    test('χωρίς φάκελο προορισμού: προειδοποίηση', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(destination: ''),
        pendingChanges: 50,
        now: now,
      );
      expect(info.hintText, contains('φάκελο προορισμού'));
      expect(info.hintIsWarning, isTrue);
    });

    test('καμία αλλαγή: το λέει καθαρά και δεν υπόσχεται αντίγραφο', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(lastAttempt: now.subtract(const Duration(hours: 2))),
        pendingChanges: 0,
        now: now,
      );
      expect(info.lastBackupText, contains('καμία — δεν χρειάζεται αντίγραφο'));
      expect(info.nextBackupText, contains('όταν υπάρξουν αλλαγές'));
      expect(info.nextIsImminent, isFalse);
    });

    test('αλλαγές κάτω από το κατώφλι: δείχνει κατώφλι ΚΑΙ προθεσμία', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(
          lastAttempt: DateTime(2026, 8, 24, 11, 0),
        ),
        pendingChanges: 7,
        now: now,
      );
      expect(info.lastBackupText, contains('Αφύλακτες αλλαγές: 7'));
      expect(info.nextBackupText, contains('στις 100 αλλαγές'));
      // Προθεσμία: 11:00 + 240΄ = 15:00.
      expect(info.nextBackupText, contains('15:00'));
    });

    test('κατώφλι γεμάτο: «εντός του επόμενου λεπτού»', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(
          lastAttempt: now.subtract(const Duration(minutes: 30)),
        ),
        pendingChanges: 120,
        now: now,
      );
      expect(info.nextBackupText, contains('εντός του επόμενου λεπτού'));
      expect(info.nextIsImminent, isTrue);
    });

    test('φρέσκο αντίγραφο με γεμάτο κατώφλι: δείχνει το «όχι πριν»', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(
          lastAttempt: DateTime(2026, 8, 24, 11, 50),
        ),
        pendingChanges: 120,
        now: now,
      );
      // 11:50 + 15΄ = 12:05.
      expect(info.nextBackupText, contains('όχι πριν τις 12:05'));
      expect(info.nextIsImminent, isFalse);
    });

    test('εργασία σε εξέλιξη: το λέει αντί για πρόβλεψη', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(),
        pendingChanges: 500,
        now: now,
        backupJobRunning: true,
      );
      expect(info.nextBackupText, contains('σε εξέλιξη τώρα'));
    });

    test('αποτυχία: προειδοποιητική υπόδειξη', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(
          lastAttempt: now.subtract(const Duration(minutes: 30)),
          lastStatus: BackupScheduleStatus.failed,
        ),
        pendingChanges: 3,
        now: now,
      );
      expect(info.hintText, contains('απέτυχε'));
      expect(info.hintIsWarning, isTrue);
    });
  });

  group('build lastBackupText', () {
    test('επιτυχία — σαφές κείμενο κατάστασης', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(
          lastAttempt: DateTime(2026, 6, 6, 18, 42),
          lastStatus: BackupScheduleStatus.success,
        ),
        pendingChanges: 0,
        now: DateTime(2026, 6, 6, 19, 0),
      );
      expect(info.lastBackupText, contains('— επιτυχία'));
      expect(info.lastBackupText, isNot(contains('— —')));
    });

    test('none χωρίς χειροκίνητο — χωρίς διπλή παύλα', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(
          lastAttempt: DateTime(2026, 6, 6, 18, 15),
          lastStatus: BackupScheduleStatus.none,
        ),
        pendingChanges: 0,
        now: DateTime(2026, 6, 6, 19, 0),
      );
      expect(info.lastBackupText, contains('χωρίς καταγεγραμμένο αποτέλεσμα'));
      expect(info.lastBackupText, isNot(contains('— —')));
    });

    test('none με νεότερο χειροκίνητο — αντικατάσταση', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(
          lastAttempt: DateTime(2026, 6, 6, 18, 15),
          lastManual: DateTime(2026, 6, 6, 19, 46),
          lastStatus: BackupScheduleStatus.none,
        ),
        pendingChanges: 0,
        now: DateTime(2026, 6, 6, 20, 0),
      );
      expect(info.lastBackupText, contains('αντικαταστάθηκε από χειροκίνητο'));
      expect(info.lastBackupText, isNot(contains('— —')));
    });
  });

  group('statsBackupHealth — η γραμμή της κάρτας Στατιστικών (Φάση 7)', () {
    test('απενεργοποιημένα: προτείνει ενεργοποίηση, με προειδοποίηση', () {
      final h = BackupScheduleStatusFormatter.statsBackupHealth(
        settings: _settings(enabled: false),
        pendingChanges: 10,
        canManageBackups: false,
        now: now,
      );
      expect(h.text, contains('απενεργοποιημένα'));
      expect(h.isWarning, isTrue);
    });

    test('καμία αλλαγή: ήσυχο πράσινο μήνυμα', () {
      final h = BackupScheduleStatusFormatter.statsBackupHealth(
        settings: _settings(lastAttempt: now.subtract(const Duration(hours: 1))),
        pendingChanges: 0,
        canManageBackups: false,
        now: now,
      );
      expect(h.text, contains('καμία'));
      expect(h.isWarning, isFalse);
    });

    test('καθυστέρηση πέρα από τη μέγιστη αναμονή: κόκκινο και για τους δύο, '
        'με διαφορετική οδηγία', () {
      final overdueAt = now.subtract(const Duration(minutes: 250));
      final admin = BackupScheduleStatusFormatter.statsBackupHealth(
        settings: _settings(lastAttempt: overdueAt),
        pendingChanges: 5,
        canManageBackups: true,
        now: now,
      );
      expect(admin.isWarning, isTrue);
      expect(admin.text, contains('καθυστερήσει'));

      final colleague = BackupScheduleStatusFormatter.statsBackupHealth(
        settings: _settings(lastAttempt: overdueAt),
        pendingChanges: 5,
        canManageBackups: false,
        now: now,
      );
      expect(colleague.isWarning, isTrue);
      expect(colleague.text, contains('ενημερώστε τον διαχειριστή'));
    });

    test('φυσιολογική εκκρεμότητα: πρόβλεψη για τον αρμόδιο, «το χειρίζεται '
        'ο διαχειριστής» για τον συνάδελφο', () {
      final lastAt = DateTime(2026, 8, 24, 11, 0);
      final admin = BackupScheduleStatusFormatter.statsBackupHealth(
        settings: _settings(lastAttempt: lastAt),
        pendingChanges: 7,
        canManageBackups: true,
        now: now,
      );
      expect(admin.isWarning, isFalse);
      expect(admin.text, contains('στις 100 αλλαγές'));
      expect(admin.text, contains('15:00'));

      final colleague = BackupScheduleStatusFormatter.statsBackupHealth(
        settings: _settings(lastAttempt: lastAt),
        pendingChanges: 7,
        canManageBackups: false,
        now: now,
      );
      expect(colleague.isWarning, isFalse);
      expect(colleague.text, contains('χειρίζεται'));
    });

    test('ακριβώς στη μέγιστη αναμονή δεν κοκκινίζει — η ανοχή αφήνει τον '
        'χρονιστή να προλάβει', () {
      final h = BackupScheduleStatusFormatter.statsBackupHealth(
        settings: _settings(
          lastAttempt: now.subtract(const Duration(minutes: 241)),
        ),
        pendingChanges: 5,
        canManageBackups: true,
        now: now,
      );
      expect(h.isWarning, isFalse);
    });
  });

  group('destinationContentLabelEl', () {
    test('folderOk — πλήρες κείμενο χωρίς διπλή αναφορά', () {
      final label = BackupScheduleStatusFormatter.destinationContentLabelEl(
        BackupDestinationContentResult(
          kind: BackupDestinationContentKind.folderOk,
          matchingBackupFileCount: 6,
          latestBackupModified: DateTime(2026, 6, 6, 20, 7),
        ),
      );
      expect(label, 'Βρέθηκαν 6 αρχεία με πιο πρόσφατο στις 06/06/2026 20:07');
    });

    test('folderOk — ενικό', () {
      final label = BackupScheduleStatusFormatter.destinationContentLabelEl(
        const BackupDestinationContentResult(
          kind: BackupDestinationContentKind.folderOk,
          matchingBackupFileCount: 1,
          latestBackupModified: null,
        ),
      );
      expect(label, 'Βρέθηκε 1 αρχείο');
    });

    test('τα μηνύματα δηλώνουν ποια βάση αφορά ο έλεγχος', () {
      final empty = BackupScheduleStatusFormatter.destinationContentLabelEl(
        const BackupDestinationContentResult(
          kind: BackupDestinationContentKind.folderEmptyNoFiles,
          dbBaseName: 'hosp',
        ),
      );
      expect(empty, contains('για τη βάση «hosp»'));

      final ok = BackupScheduleStatusFormatter.destinationContentLabelEl(
        const BackupDestinationContentResult(
          kind: BackupDestinationContentKind.folderOk,
          matchingBackupFileCount: 3,
          dbBaseName: 'hosp',
        ),
      );
      expect(ok, contains('για τη βάση «hosp»'));
    });
  });
}
