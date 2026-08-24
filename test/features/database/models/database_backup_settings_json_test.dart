import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseBackupSettings JSON — ρυθμίσεις πυροδότησης (Φάση 3)', () {
    test('κύκλος αποθήκευσης/ανάγνωσης διατηρεί μετρητή και κατώφλια', () {
      final settings = DatabaseBackupSettings.defaults().copyWith(
        destinationDirectory: r'C:\Backups',
        backupOnExit: true,
        changeThreshold: 250,
        minSpacingMinutes: 30,
        maxWaitMinutes: 480,
        backupOnCloseIfPending: false,
        lastBackupAuditId: 41237,
      );

      final restored = DatabaseBackupSettings.fromJsonString(
        settings.toJsonString(),
      );

      expect(restored.changeThreshold, 250);
      expect(restored.minSpacingMinutes, 30);
      expect(restored.maxWaitMinutes, 480);
      expect(restored.backupOnCloseIfPending, isFalse);
      expect(restored.lastBackupAuditId, 41237);
      expect(restored, settings);
    });

    test('κύκλος αποθήκευσης/ανάγνωσης διατηρεί αποτύπωμα και διατήρηση '
        'δύο γραμμών (Φάσεις 5–6)', () {
      final settings = DatabaseBackupSettings.defaults().copyWith(
        lastFullBackupFingerprint: 'v1:12:abc123',
        lastFullBackupAt: DateTime(2026, 8, 24, 9, 12),
        retentionQuickMaxCopies: 24,
        retentionQuickMaxAgeDays: 3,
        retentionFullMaxCopiesEnabled: false,
        retentionFullMaxCopies: 9,
      );

      final restored = DatabaseBackupSettings.fromJsonString(
        settings.toJsonString(),
      );

      expect(restored.lastFullBackupFingerprint, 'v1:12:abc123');
      expect(restored.lastFullBackupAt, DateTime(2026, 8, 24, 9, 12));
      expect(restored.retentionQuickMaxCopies, 24);
      expect(restored.retentionQuickMaxAgeDays, 3);
      expect(restored.retentionFullMaxCopiesEnabled, isFalse);
      expect(restored.retentionFullMaxCopies, 9);
      expect(restored, settings);
    });

    test(
      'JSON παλιάς έκδοσης (ημερολογιακό πρόγραμμα) διαβάζεται με προεπιλογές '
      'πυροδότησης — τα νεκρά πεδία αγνοούνται',
      () {
        final restored = DatabaseBackupSettings.fromJsonString(
          '{"destinationDirectory":"C:\\\\Backups","backupOnExit":true,'
          '"backupDays":[6],"backupTime":"18:42","interval":1,'
          '"scheduleAnchorAt":"2026-07-27T09:30:00.000",'
          '"lastBackupStatus":"missed"}',
        );

        expect(restored.destinationDirectory, r'C:\Backups');
        expect(restored.backupOnExit, isTrue);
        expect(restored.changeThreshold, 100);
        expect(restored.minSpacingMinutes, 15);
        expect(restored.maxWaitMinutes, 240);
        expect(restored.backupOnCloseIfPending, isTrue);
        expect(restored.lastBackupAuditId, isNull);
        expect(
          restored.lastBackupStatus,
          'none',
          reason: 'Το «χάθηκε» δεν υπάρχει πια — κανονικοποιείται σιωπηλά.',
        );
      },
    );

    test('η ελάχιστη απόσταση δεν πέφτει κάτω από το όριο των 15΄', () {
      final restored = DatabaseBackupSettings.fromJsonString(
        '{"minSpacingMinutes":3,"maxWaitMinutes":5}',
      );
      expect(
        restored.minSpacingMinutes,
        DatabaseBackupSettings.minAllowedSpacingMinutes,
      );
      expect(
        restored.maxWaitMinutes,
        DatabaseBackupSettings.minAllowedSpacingMinutes,
      );
    });
  });
}
