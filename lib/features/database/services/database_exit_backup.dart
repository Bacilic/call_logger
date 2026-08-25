import '../../../core/database/backup_pending_changes.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/app_permission.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/permission_service.dart';
import '../utils/backup_schedule_utils.dart';
import '../utils/backup_trigger_decision.dart';
import 'active_backup_settings.dart';
import 'backup_responsibility.dart';
import 'database_backup_audit.dart';
import 'database_backup_service.dart';

/// Αντίγραφο κατά το κλείσιμο παραθύρου (Windows): η τελευταία ευκαιρία να
/// προστατευτούν οι αφύλακτες αλλαγές — τρέχει μόνο όταν υπάρχουν (Φάση 3),
/// χωρίς κατώφλι ή αποστάσεις.
///
/// Διαβάζει και γράφει τις ρυθμίσεις μέσα από την [ActiveBackupSettings] — την
/// ίδια πύλη με το ζωντανό μονοπάτι — και σέβεται το δικαίωμα του πλήρους
/// αντιγράφου, όπως και ο χρονιστής.
class DatabaseExitBackup {
  DatabaseExitBackup._();

  static bool _runInProgress = false;

  static Future<void> runIfEnabled() async {
    if (_runInProgress) return;
    _runInProgress = true;
    try {
      // Ίδιο σημείο ελέγχου με τον χρονιστή: χωρίς το δικαίωμα, το κλείσιμο
      // του συναδέλφου δεν επιτρέπεται να πάρει το αντίγραφο που η οθόνη του
      // λέει ότι «το χειρίζεται ο διαχειριστής».
      if (!PermissionService.instance.can(AppPermission.fullBackup)) return;

      final gate = await ActiveBackupSettings.readWithRaw();
      final settings = gate.settings;
      final db = await DatabaseHelper.instance.database;
      final pendingRepo = BackupPendingChangesRepository(db);
      final pending = await pendingRepo.countPendingSince(
        settings.lastBackupAuditId,
        fallbackSince: settings.lastAnyBackupAt,
      );
      if (!BackupTriggerDecision.shouldRunOnClose(
        settings: settings,
        pendingChanges: pending,
      )) {
        return;
      }

      // Φάση 4: με παρόντα διαχειριστή, ο χρονιστής εκείνου θα καλύψει τις
      // αλλαγές — ο εφεδρικός δεν παίρνει αντίγραφο στο δικό του κλείσιμο.
      if (await BackupResponsibility.shouldDeferToPresentAdmin(
        current: CurrentOperator.active,
        now: DateTime.now(),
      )) {
        return;
      }

      // Ατομική δέσμευση, όπως στον χρονιστή: αν άλλο μηχάνημα μόλις άλλαξε
      // το δέμα (π.χ. πήρε το αντίγραφο), το κλείσιμο κάνει πίσω.
      final claimed = settings.copyWith(lastBackupAttempt: DateTime.now());
      if (!await ActiveBackupSettings.tryReplace(
        expectedRaw: gate.raw,
        replacement: claimed,
      )) {
        return;
      }

      final result = await DatabaseBackupService.runBackup(
        claimed,
        requireDestination: true,
        auditTrigger: BackupAuditTrigger.onExit,
      );

      // Στοχευμένη εγγραφή, όχι ολόκληρο το δεσμευμένο δέμα: όσο έτρεχε το
      // αντίγραφο, ο διαχειριστής στο άλλο μηχάνημα μπορεί να άλλαξε επιλογή.
      if (result.success) {
        // Σημάδι ΜΕΤΑ την audit εγγραφή του αντιγράφου — η ίδια δεν μετρά
        // ως νέα αφύλακτη αλλαγή.
        final markId = await pendingRepo.latestAuditId();
        final finishedAt = DateTime.now();
        final fullAt = result.isFullBackup ? finishedAt : null;
        await ActiveBackupSettings.update(
          (current) => current.copyWith(
            lastBackupAuditId: markId,
            lastBackupAttempt: finishedAt,
            lastBackupStatus: BackupScheduleStatus.success,
            lastFullBackupFingerprint: result.portableFingerprint,
            lastFullBackupAt: fullAt,
          ),
        );
      } else {
        await ActiveBackupSettings.update(
          (current) => current.copyWith(
            lastBackupStatus:
                result.failureCode == DatabaseBackupFailureCode.folderMissing
                ? BackupScheduleStatus.folderMissing
                : BackupScheduleStatus.failed,
          ),
        );
      }
    } finally {
      _runInProgress = false;
    }
  }
}
