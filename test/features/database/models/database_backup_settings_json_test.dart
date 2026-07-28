import 'package:call_logger/features/database/models/database_backup_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatabaseBackupSettings JSON — σημείο αναφοράς προγράμματος', () {
    test('κύκλος αποθήκευσης/ανάγνωσης διατηρεί το scheduleAnchorAt', () {
      final settings = DatabaseBackupSettings.defaults().copyWith(
        destinationDirectory: r'C:\Backups',
        backupOnExit: true,
        backupDays: const [6],
        backupTime: '18:42',
        scheduleAnchorAt: DateTime(2026, 7, 27, 9, 30),
      );

      final restored = DatabaseBackupSettings.fromJsonString(
        settings.toJsonString(),
      );

      expect(restored.scheduleAnchorAt, DateTime(2026, 7, 27, 9, 30));
      expect(restored, settings);
    });

    test('παλιό JSON χωρίς το πεδίο διαβάζεται με null αγκύρωση', () {
      final restored = DatabaseBackupSettings.fromJsonString(
        '{"destinationDirectory":"C:\\\\Backups","backupOnExit":true,'
        '"backupDays":[6],"backupTime":"18:42","lastBackupStatus":"none"}',
      );

      expect(restored.scheduleAnchorAt, isNull);
      expect(restored.backupDays, const [6]);
    });
  });
}
