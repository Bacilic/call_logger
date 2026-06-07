import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:call_logger/features/database/utils/backup_destination_folder_validator.dart';
import 'package:call_logger/features/database/utils/backup_schedule_status.dart';
import 'package:call_logger/features/database/utils/backup_schedule_utils.dart';
import 'package:flutter_test/flutter_test.dart';

DatabaseBackupSettings _settings({
  List<int> days = const [6],
  String time = '18:42',
  DateTime? lastAttempt,
  String lastStatus = BackupScheduleStatus.none,
}) =>
    DatabaseBackupSettings(
      destinationDirectory: r'C:\Backups',
      namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
      zipOutput: false,
      includeMapImagesInBackup: false,
      includeToolImages: true,
      includeLexicon: false,
      includeLampDb: false,
      backupOnExit: true,
      interval: DatabaseBackupInterval.never,
      backupDays: days,
      backupTime: time,
    lastBackupAttempt: lastAttempt,
    lastManualBackupAttempt: null,
    lastBackupStatus: lastStatus,
      retentionMaxCopiesEnabled: false,
      retentionMaxCopies: 30,
      retentionMaxAgeEnabled: false,
      retentionMaxAgeDays: 60,
    );

void main() {
  test('nextScheduleInstant μελλοντική ώρα σήμερα', () {
    final now = DateTime(2026, 6, 6, 18, 30);
    final next = BackupScheduleStatusFormatter.nextScheduleInstant(
      now,
      const [6],
      '18:42',
    );
    expect(next, DateTime(2026, 6, 6, 18, 42));
  });

  test('nextScheduleInstant πηγαίνει στην επόμενη ημέρα αν έχει ήδη τρέξει σήμερα', () {
    final now = DateTime(2026, 6, 6, 18, 50);
    final last = DateTime(2026, 6, 6, 18, 12);
    final next = BackupScheduleStatusFormatter.nextScheduleInstant(
      now,
      const [6],
      '18:42',
      lastBackupAttempt: last,
    );
    expect(next, DateTime(2026, 6, 13, 18, 42));
  });

  test('build εμφανίζει προειδοποίηση όταν έχει ήδη τρέξει σήμερα', () {
    final info = BackupScheduleStatusFormatter.build(
      settings: _settings(
        lastAttempt: DateTime(2026, 6, 6, 18, 12),
        lastStatus: BackupScheduleStatus.success,
      ),
      now: DateTime(2026, 6, 6, 18, 50),
    );
    expect(info.hintText, contains('ήδη εκτελεστεί'));
    expect(info.nextBackupText, isNot(contains('εντός του επόμενου λεπτού')));
  });

  test('shouldMarkScheduleMissed false όταν έχει τρέξει προγραμματισμένο σήμερα', () {
    final now = DateTime(2026, 6, 6, 18, 50);
    expect(
      BackupScheduleStatusFormatter.shouldMarkScheduleMissed(
        _settings(
          time: '18:42',
          lastAttempt: DateTime(2026, 6, 6, 18, 12),
          lastStatus: BackupScheduleStatus.success,
        ),
        now,
      ),
      isFalse,
    );
  });

  test('shouldMarkScheduleMissed false σε μη προγραμματισμένη ημέρα', () {
    // 2026-06-07 = Κυριακή (7), πρόγραμμα μόνο Σάββατο (6)
    expect(
      BackupScheduleStatusFormatter.shouldMarkScheduleMissed(
        _settings(
          days: const [6],
          time: '18:42',
          lastAttempt: DateTime(2026, 6, 6, 18, 15),
          lastStatus: BackupScheduleStatus.none,
        ),
        DateTime(2026, 6, 7, 10, 0),
      ),
      isFalse,
    );
  });

  test('shouldMarkScheduleMissed false Κυριακή με χειροκίνητο Σάββατο', () {
    final settings = DatabaseBackupSettings(
      destinationDirectory: r'C:\Backups',
      namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
      zipOutput: false,
      includeMapImagesInBackup: false,
      includeToolImages: true,
      includeLexicon: false,
      includeLampDb: false,
      backupOnExit: true,
      interval: DatabaseBackupInterval.never,
      backupDays: const [6],
      backupTime: '18:42',
      lastBackupAttempt: DateTime(2026, 6, 6, 18, 15),
      lastManualBackupAttempt: DateTime(2026, 6, 6, 19, 46),
      lastBackupStatus: BackupScheduleStatus.missed,
      retentionMaxCopiesEnabled: false,
      retentionMaxCopies: 30,
      retentionMaxAgeEnabled: false,
      retentionMaxAgeDays: 60,
    );
    expect(
      BackupScheduleStatusFormatter.shouldMarkScheduleMissed(
        settings,
        DateTime(2026, 6, 7, 10, 0),
      ),
      isFalse,
    );
    expect(
      BackupScheduleStatusFormatter.shouldShowBackupMissedAlert(
        settings,
        DateTime(2026, 6, 7, 10, 0),
      ),
      isFalse,
    );
  });

  test('shouldMarkScheduleMissed false πριν την προγραμματισμένη ώρα', () {
    expect(
      BackupScheduleStatusFormatter.shouldMarkScheduleMissed(
        _settings(days: const [6], time: '18:42'),
        DateTime(2026, 6, 6, 18, 30),
      ),
      isFalse,
    );
  });

  test('shouldMarkScheduleMissed true Σάββατο μετά την ώρα χωρίς αντίγραφο', () {
    expect(
      BackupScheduleStatusFormatter.shouldMarkScheduleMissed(
        _settings(days: const [6], time: '18:42'),
        DateTime(2026, 6, 6, 19, 0),
      ),
      isTrue,
    );
  });

  test('shouldMarkScheduleMissed false με χειροκίνητο σήμερα', () {
    final now = DateTime(2026, 6, 6, 18, 50);
    final settings = DatabaseBackupSettings(
      destinationDirectory: r'C:\Backups',
      namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
      zipOutput: false,
      includeMapImagesInBackup: false,
      includeToolImages: true,
      includeLexicon: false,
      includeLampDb: false,
      backupOnExit: true,
      interval: DatabaseBackupInterval.never,
      backupDays: const [6],
      backupTime: '18:42',
      lastBackupAttempt: null,
      lastManualBackupAttempt: DateTime(2026, 6, 6, 17, 30),
      lastBackupStatus: BackupScheduleStatus.none,
      retentionMaxCopiesEnabled: false,
      retentionMaxCopies: 30,
      retentionMaxAgeEnabled: false,
      retentionMaxAgeDays: 60,
    );
    expect(
      BackupScheduleStatusFormatter.shouldMarkScheduleMissed(settings, now),
      isFalse,
    );
  });

  test('build imminent όταν η ώρα έχει περάσει και δεν έχει τρέξει σήμερα', () {
    final info = BackupScheduleStatusFormatter.build(
      settings: _settings(),
      now: DateTime(2026, 6, 6, 18, 43),
    );
    expect(info.nextIsImminent, isTrue);
    expect(info.nextBackupText, contains('επόμενου λεπτού'));
  });

  group('build lastBackupText', () {
    test('επιτυχία — σαφές κείμενο κατάστασης', () {
      final info = BackupScheduleStatusFormatter.build(
        settings: _settings(
          lastAttempt: DateTime(2026, 6, 6, 18, 42),
          lastStatus: BackupScheduleStatus.success,
        ),
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
        now: DateTime(2026, 6, 6, 19, 0),
      );
      expect(
        info.lastBackupText,
        contains('χωρίς καταγεγραμμένο αποτέλεσμα'),
      );
      expect(info.lastBackupText, isNot(contains('— —')));
    });

    test('none με νεότερο χειροκίνητο — αντικατάσταση', () {
      final settings = DatabaseBackupSettings(
        destinationDirectory: r'C:\Backups',
        namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
        zipOutput: false,
        includeMapImagesInBackup: false,
        includeToolImages: true,
        includeLexicon: false,
        includeLampDb: false,
        backupOnExit: true,
        interval: DatabaseBackupInterval.never,
        backupDays: const [6],
        backupTime: '18:42',
        lastBackupAttempt: DateTime(2026, 6, 6, 18, 15),
        lastManualBackupAttempt: DateTime(2026, 6, 6, 19, 46),
        lastBackupStatus: BackupScheduleStatus.none,
        retentionMaxCopiesEnabled: false,
        retentionMaxCopies: 30,
        retentionMaxAgeEnabled: false,
        retentionMaxAgeDays: 60,
      );
      final info = BackupScheduleStatusFormatter.build(
        settings: settings,
        now: DateTime(2026, 6, 6, 20, 0),
      );
      expect(info.lastBackupText, contains('αντικαταστάθηκε από χειροκίνητο'));
      expect(info.lastBackupText, isNot(contains('— —')));
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
      expect(
        label,
        'Βρέθηκαν 6 αρχεία με πιο πρόσφατο στις 06/06/2026 20:07',
      );
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
  });

  group('shouldRunExitBackup', () {
    test('false σε μη προγραμματισμένη ημέρα', () {
      // 2026-06-04 = Τετάρτη (weekday 3), πρόγραμμα μόνο Παρασκευή (6)
      expect(
        BackupScheduleStatusFormatter.shouldRunExitBackup(
          _settings(days: const [6], time: '09:00'),
          DateTime(2026, 6, 4, 18, 0),
        ),
        isFalse,
      );
    });

    test('false πριν την προγραμματισμένη ώρα', () {
      expect(
        BackupScheduleStatusFormatter.shouldRunExitBackup(
          _settings(days: const [6], time: '18:42'),
          DateTime(2026, 6, 6, 18, 30),
        ),
        isFalse,
      );
    });

    test('false με επιτυχές προγραμματισμένο σήμερα', () {
      expect(
        BackupScheduleStatusFormatter.shouldRunExitBackup(
          _settings(
            days: const [6],
            time: '18:42',
            lastAttempt: DateTime(2026, 6, 6, 18, 45),
            lastStatus: BackupScheduleStatus.success,
          ),
          DateTime(2026, 6, 6, 19, 0),
        ),
        isFalse,
      );
    });

    test('false με χειροκίνητο αντίγραφο σήμερα', () {
      final settings = DatabaseBackupSettings(
        destinationDirectory: r'C:\Backups',
        namingFormat: DatabaseBackupNamingFormat.dateTimeThenBase,
        zipOutput: false,
        includeMapImagesInBackup: false,
        includeToolImages: true,
        includeLexicon: false,
        includeLampDb: false,
        backupOnExit: true,
        interval: DatabaseBackupInterval.never,
        backupDays: const [6],
        backupTime: '18:42',
        lastBackupAttempt: null,
        lastManualBackupAttempt: DateTime(2026, 6, 6, 17, 30),
        lastBackupStatus: BackupScheduleStatus.none,
        retentionMaxCopiesEnabled: false,
        retentionMaxCopies: 30,
        retentionMaxAgeEnabled: false,
        retentionMaxAgeDays: 60,
      );
      expect(
        BackupScheduleStatusFormatter.shouldRunExitBackup(
          settings,
          DateTime(2026, 6, 6, 19, 0),
        ),
        isFalse,
      );
    });

    test('true μετά την ώρα χωρίς προσπάθεια σήμερα', () {
      expect(
        BackupScheduleStatusFormatter.shouldRunExitBackup(
          _settings(days: const [6], time: '18:42'),
          DateTime(2026, 6, 6, 19, 0),
        ),
        isTrue,
      );
    });

    test('true μετά την ώρα με αποτυχημένο προγραμματισμένο σήμερα', () {
      expect(
        BackupScheduleStatusFormatter.shouldRunExitBackup(
          _settings(
            days: const [6],
            time: '18:42',
            lastAttempt: DateTime(2026, 6, 6, 18, 45),
            lastStatus: BackupScheduleStatus.failed,
          ),
          DateTime(2026, 6, 6, 19, 0),
        ),
        isTrue,
      );
    });

    test('true μετά την ώρα με κατάσταση missed', () {
      expect(
        BackupScheduleStatusFormatter.shouldRunExitBackup(
          _settings(
            days: const [6],
            time: '18:42',
            lastStatus: BackupScheduleStatus.missed,
          ),
          DateTime(2026, 6, 6, 19, 0),
        ),
        isTrue,
      );
    });
  });
}
