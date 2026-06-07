import 'package:call_logger/features/database/services/database_backup_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('skipReasonMessageEl για ήδη εκτελεσμένο σήμερα', () {
    expect(
      DatabaseBackupAudit.skipReasonMessageEl(
        BackupAuditSkipReason.alreadyRanToday,
      ),
      contains('ήδη εκτελεστεί'),
    );
  });

  test('triggerLabelEl για προγραμματισμένο', () {
    expect(
      DatabaseBackupAudit.triggerLabelEl(BackupAuditTrigger.scheduled),
      'προγραμματισμένο',
    );
  });
}
