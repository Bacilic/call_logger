import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/backup_pending_changes.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/app_permission.dart';
import '../../../core/providers/active_critical_operations_provider.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/permission_service.dart';
import '../models/database_backup_settings.dart';
import '../services/active_backup_settings.dart';
import '../services/backup_responsibility.dart';
import '../services/database_backup_audit.dart';
import '../services/database_backup_service.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_schedule_utils.dart';
import '../utils/backup_trigger_decision.dart';
import 'database_backup_settings_provider.dart';

/// Χρονιστής αυτόματων αντιγράφων: έλεγχος κάθε 1 λεπτό με βάση τον μετρητή
/// αλλαγών του Ιστορικού (Φάση 3) — όχι ημερολογιακό πρόγραμμα.
///
/// Σε κάθε τικ οι ρυθμίσεις ξαναφορτώνονται από τη βάση: είναι κοινές, και το
/// σημάδι «μέχρι πού είναι φυλαγμένες οι αλλαγές» μπορεί να το έχει μόλις
/// προχωρήσει άλλο μηχάνημα — μια παλιά τιμή στη μνήμη θα οδηγούσε σε διπλό
/// αντίγραφο.
final backupSchedulerProvider = NotifierProvider<BackupSchedulerNotifier, int>(
  BackupSchedulerNotifier.new,
);

class BackupSchedulerNotifier extends Notifier<int> {
  Timer? _timer;
  bool _runLock = false;
  String? _skipAuditLoggedKey;

  /// True όσο τρέχει αυτόματο αντίγραφο ασφαλείας.
  bool get isBackupJobRunning => _runLock;

  @override
  int build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return 0;
  }

  /// Φόρτωση ρυθμίσεων, έλεγχος φακέλου προορισμού, εκκίνηση περιοδικού ελέγχου.
  Future<void> checkStartupAndStart() async {
    await ref.read(databaseBackupSettingsProvider.notifier).load();
    final settings = ref.read(databaseBackupSettingsProvider);
    await checkDestinationFolderStatus(settings);
    startTimer();
  }

  void startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_tick());
    });
  }

  void _maybeLogScheduledSkip(
    DatabaseBackupSettings settings,
    String skipReason,
  ) {
    // Μία καταγραφή ανά ημέρα και αιτία — όχι θόρυβος σε κάθε τικ.
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final key = '$today:$skipReason';
    if (_skipAuditLoggedKey == key) return;
    _skipAuditLoggedKey = key;
    unawaited(
      DatabaseBackupAudit.logScheduledSkip(
        skipReason: skipReason,
        destination: settings.destinationDirectory.trim(),
      ),
    );
  }

  /// Αναβάθμιση failed σε folder_missing όταν λείπει ο φάκελος· καθάρισμα όταν επανέρχεται.
  Future<void> checkDestinationFolderStatus(
    DatabaseBackupSettings settings,
  ) async {
    if (!settings.backupOnExit) return;
    final dest = settings.destinationDirectory.trim();
    if (dest.isEmpty) return;

    final db = await DatabaseHelper.instance.database;
    final baseName = p.basenameWithoutExtension(db.path);
    final content =
        await BackupDestinationFolderValidator.inspectDestinationContent(
          destinationDirectory: dest,
          dbBaseName: baseName,
        );

    final notifier = ref.read(databaseBackupSettingsProvider.notifier);
    final st = BackupScheduleStatus.normalize(settings.lastBackupStatus);

    if (content.kind == BackupDestinationContentKind.folderMissing) {
      if (st == BackupScheduleStatus.failed) {
        await notifier.setLastBackupStatus(BackupScheduleStatus.folderMissing);
        state = state + 1;
      }
      return;
    }

    if (st == BackupScheduleStatus.folderMissing) {
      await notifier.setLastBackupStatus(BackupScheduleStatus.none);
      state = state + 1;
    }
  }

  /// Ένα τικ του χρονιστή, εκτός Timer — για τα τεστ.
  @visibleForTesting
  Future<void> debugRunTick() => _tick();

  Future<void> _tick() async {
    // Το πλήρες αντίγραφο είναι δικαίωμα. Ο έλεγχος γίνεται σε κάθε τικ —
    // η «Αλλαγή χρήστη» αλλάζει την απάντηση ζωντανά.
    if (!PermissionService.instance.can(AppPermission.fullBackup)) return;

    final notifier = ref.read(databaseBackupSettingsProvider.notifier);

    // Φρέσκια ανάγνωση από τη βάση (με το ωμό JSON για τη δέσμευση) — το
    // σημάδι μπορεί να το προχώρησε μόλις άλλο μηχάνημα.
    final ({DatabaseBackupSettings settings, String? raw}) gate;
    final int pending;
    try {
      gate = await ActiveBackupSettings.readWithRaw();
      final db = await DatabaseHelper.instance.database;
      pending = await BackupPendingChangesRepository(db).countPendingSince(
        gate.settings.lastBackupAuditId,
        fallbackSince: gate.settings.lastAnyBackupAt,
      );
    } catch (_) {
      // Χωρίς προσβάσιμη βάση δεν υπάρχει ούτε κάτι να αντιγραφεί.
      return;
    }
    final settings = gate.settings;
    notifier.adopt(settings);

    final decision = BackupTriggerDecision.evaluate(
      settings: settings,
      pendingChanges: pending,
      now: DateTime.now(),
    );
    if (!decision.due) {
      // Οφειλόμενες αλλαγές που μπλοκάρουν σε ρύθμιση: μία καταγραφή την ημέρα.
      if (pending >= settings.changeThreshold) {
        if (decision.reason == BackupTriggerReason.disabled) {
          _maybeLogScheduledSkip(
            settings,
            BackupAuditSkipReason.backupDisabled,
          );
        } else if (decision.reason == BackupTriggerReason.noDestination) {
          _maybeLogScheduledSkip(settings, BackupAuditSkipReason.noDestination);
        }
      }
      return;
    }

    if (_runLock) {
      _maybeLogScheduledSkip(settings, BackupAuditSkipReason.jobRunning);
      return;
    }

    // Αντίστροφη φορά του ελέγχου που κάνει ο φρουρός εναλλαγής βάσης: εκείνος
    // μπλοκάρει την αλλαγή όσο τρέχει αντίγραφο· εδώ αποφεύγουμε να ξεκινήσει
    // αντίγραφο πάνω σε βάση που αλλάζει αυτή τη στιγμή (VACUUM INTO σε handle
    // που πρόκειται να κλείσει → μισό/αποτυχημένο αντίγραφο ή λάθος βάση).
    if (ref
        .read(activeCriticalOperationsProvider)
        .contains(CriticalOperation.databaseSwitch)) {
      _maybeLogScheduledSkip(
        settings,
        BackupAuditSkipReason.databaseSwitchInProgress,
      );
      return;
    }

    // Φάση 4: «είμαι ο πρώτος διαθέσιμος;» — ο παρών διαχειριστής προηγείται.
    // Φυσιολογική λειτουργία του εφεδρικού, όχι ανωμαλία — χωρίς audit.
    if (await BackupResponsibility.shouldDeferToPresentAdmin(
      current: CurrentOperator.active,
      now: DateTime.now(),
    )) {
      return;
    }

    // Ατομική δέσμευση: η προσπάθεια σφραγίζεται ΠΡΙΝ τρέξει το αντίγραφο.
    // Όποιος χάσει την κούρσα (άλλο μηχάνημα, δεύτερος εφεδρικός) βλέπει
    // false και κάνει πίσω· στο επόμενο τικ θα δει το φρέσκο σημάδι.
    final claimed = settings.copyWith(lastBackupAttempt: DateTime.now());
    if (!await ActiveBackupSettings.tryReplace(
      expectedRaw: gate.raw,
      replacement: claimed,
    )) {
      return;
    }
    notifier.adopt(claimed);

    _runLock = true;
    try {
      final result = await DatabaseBackupFileOperation.run(
        claimed,
        auditTrigger: BackupAuditTrigger.scheduled,
      );

      // Η σφραγίδα γράφεται ΠΑΝΩ ΣΤΗ ΦΡΕΣΚΙΑ τιμή, όχι πάνω στη δεσμευμένη:
      // το αντίγραφο κρατά δευτερόλεπτα έως λεπτά, και στο μεταξύ ο
      // διαχειριστής μπορεί να άλλαξε μια επιλογή από την οθόνη ρυθμίσεων.
      // Γράφοντας ολόκληρο το `claimed` θα την επαναφέραμε αθόρυβα.
      final DatabaseBackupSettings done;
      if (result.success) {
        // Το σημάδι παίρνεται ΜΕΤΑ το αντίγραφο και την audit εγγραφή του:
        // έτσι η ίδια η εγγραφή «ΕΠΙΤΥΧΙΑ» δεν μετρά ως νέα αφύλακτη αλλαγή.
        final db = await DatabaseHelper.instance.database;
        final markId = await BackupPendingChangesRepository(db).latestAuditId();
        // Οι χρονοσφραγίδες υπολογίζονται ΜΙΑ φορά: η στοχευμένη εγγραφή
        // μπορεί να ξαναδοκιμάσει, και δύο προσπάθειες δεν επιτρέπεται να
        // δώσουν διαφορετική ώρα για το ίδιο αντίγραφο.
        final finishedAt = DateTime.now();
        final fullAt = result.isFullBackup ? finishedAt : null;
        done = await ActiveBackupSettings.update(
          (current) => current.copyWith(
            lastBackupAuditId: markId,
            lastBackupAttempt: finishedAt,
            lastBackupStatus: BackupScheduleStatus.success,
            lastFullBackupFingerprint: result.portableFingerprint,
            lastFullBackupAt: fullAt,
          ),
        );
      } else {
        done = await ActiveBackupSettings.update(
          (current) => current.copyWith(
            lastBackupStatus:
                result.failureCode == DatabaseBackupFailureCode.folderMissing
                ? BackupScheduleStatus.folderMissing
                : BackupScheduleStatus.failed,
          ),
        );
      }
      notifier.adopt(done);
      state = state + 1;
    } finally {
      _runLock = false;
    }
  }
}
