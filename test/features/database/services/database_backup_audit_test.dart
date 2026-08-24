import 'package:call_logger/features/database/services/database_backup_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('skipReasonMessageEl για απενεργοποιημένα αντίγραφα', () {
    expect(
      DatabaseBackupAudit.skipReasonMessageEl(
        BackupAuditSkipReason.backupDisabled,
      ),
      contains('απενεργοποιημένα'),
    );
  });

  test('triggerLabelEl για προγραμματισμένο', () {
    expect(
      DatabaseBackupAudit.triggerLabelEl(BackupAuditTrigger.scheduled),
      'προγραμματισμένο',
    );
  });
}
