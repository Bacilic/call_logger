import 'package:intl/intl.dart';

import '../../../core/utils/greek_date_format.dart';
import '../models/database_backup_settings.dart';
import 'backup_destination_folder_validator.dart';
import 'backup_schedule_utils.dart';
import 'backup_trigger_decision.dart';

/// Πληροφορίες εμφάνισης για την κατάσταση των αυτόματων αντιγράφων.
class BackupScheduleStatusInfo {
  const BackupScheduleStatusInfo({
    this.nextBackupText,
    this.lastBackupText,
    this.hintText,
    this.hintIsWarning = false,
    this.nextIsImminent = false,
  });

  final String? nextBackupText;
  final String? lastBackupText;
  final String? hintText;
  final bool hintIsWarning;
  final bool nextIsImminent;
}

/// Μορφοποίηση κατάστασης αυτόματων αντιγράφων για το UI (Φάση 3: μετρητής
/// αλλαγών αντί για ημερολογιακό πρόγραμμα).
abstract final class BackupScheduleStatusFormatter {
  BackupScheduleStatusFormatter._();

  static String formatLocalTimeHm(DateTime local) {
    final l = local.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final min = l.minute.toString().padLeft(2, '0');
    return '$hh:$min';
  }

  static String formatLocalDateTime(DateTime local) {
    final w = weekdayShortElTitle(local);
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$w $dd-$mm-$yyyy $hh:$min';
  }

  static String _formatLastRecordedAttemptLine(
    DatabaseBackupSettings settings, {
    String? dbBaseName,
  }) {
    // Οι ρυθμίσεις (και το ιστορικό προσπαθειών) ζουν ΜΕΣΑ σε κάθε βάση, οπότε
    // η γραμμή δηλώνει ρητά ποια βάση αφορά — μετά από αλλαγή βάσης το «καμία
    // καταγραφή» αλλιώς μοιάζει με χαμένο ιστορικό.
    final base = dbBaseName?.trim() ?? '';
    final scope = base.isEmpty ? '' : ' (βάση «$base»)';
    final last = settings.lastBackupAttempt;
    if (last == null) {
      return 'Τελευταία καταγεγραμμένη προσπάθεια$scope: καμία καταγραφή.';
    }

    final datePart = formatLocalDateTime(last.toLocal());
    final prefix = 'Τελευταία καταγεγραμμένη προσπάθεια$scope:';

    switch (BackupScheduleStatus.normalize(settings.lastBackupStatus)) {
      case BackupScheduleStatus.success:
        return '$prefix $datePart — επιτυχία';
      case BackupScheduleStatus.failed:
        return '$prefix $datePart — αποτυχία';
      case BackupScheduleStatus.folderMissing:
        return '$prefix $datePart — φάκελος λείπει';
      case BackupScheduleStatus.none:
        final manual = settings.lastManualBackupAttempt;
        if (manual != null && manual.toLocal().isAfter(last.toLocal())) {
          final manualPart = formatLocalDateTime(manual.toLocal());
          return '$prefix $datePart — χωρίς ολοκληρωμένο αποτέλεσμα '
              '(αντικαταστάθηκε από χειροκίνητο αντίγραφο στις $manualPart)';
        }
        return '$prefix $datePart — χωρίς καταγεγραμμένο αποτέλεσμα';
      default:
        return '$prefix $datePart — χωρίς καταγεγραμμένο αποτέλεσμα';
    }
  }

  static String destinationContentLabelEl(
    BackupDestinationContentResult content,
  ) {
    // Τα αρχεία αντιγράφου ταιριάζονται με το όνομα της τρέχουσας βάσης, οπότε
    // το μήνυμα πρέπει να λέει ΠΟΙΑ βάση αφορά: μετά από αλλαγή βάσης ο ίδιος
    // φάκελος μπορεί να είναι γεμάτος αντίγραφα άλλης βάσης.
    final base = content.dbBaseName.trim();
    final forBase = base.isEmpty ? '' : ' για τη βάση «$base»';
    switch (content.kind) {
      case BackupDestinationContentKind.folderNotSet:
        return 'δεν έχει οριστεί φάκελος προορισμού';
      case BackupDestinationContentKind.folderMissing:
        return 'ο φάκελος προορισμού δεν υπάρχει';
      case BackupDestinationContentKind.folderEmptyNoFiles:
        return 'ο φάκελος υπάρχει αλλά δεν βρέθηκαν αρχεία αντιγράφου$forBase';
      case BackupDestinationContentKind.folderOk:
        final n = content.matchingBackupFileCount;
        final latest = content.latestBackupModified;
        final countPart = n == 1 ? '1 αρχείο$forBase' : '$n αρχεία$forBase';
        if (latest == null) {
          return n == 1 ? 'Βρέθηκε $countPart' : 'Βρέθηκαν $countPart';
        }
        final stamp = DateFormat('dd/MM/yyyy HH:mm').format(latest.toLocal());
        return n == 1
            ? 'Βρέθηκε $countPart με πιο πρόσφατο στις $stamp'
            : 'Βρέθηκαν $countPart με πιο πρόσφατο στις $stamp';
    }
  }

  /// Γραμμή «Αφύλακτες αλλαγές: Ν».
  static String pendingChangesLine(int pendingChanges) => pendingChanges == 0
      ? 'Αφύλακτες αλλαγές: καμία — δεν χρειάζεται αντίγραφο.'
      : 'Αφύλακτες αλλαγές: $pendingChanges.';

  /// Πόσα λεπτά ανοχής πριν το «καθυστερεί»: σε κανονική λειτουργία το
  /// οφειλόμενο αντίγραφο παίρνεται μέσα σε ένα λεπτό από τη μέγιστη αναμονή —
  /// κόκκινο νωρίτερα θα αναβόσβηνε σε κάθε φυσιολογικό κύκλο.
  static const int _overdueGraceMinutes = 5;

  /// Η γραμμή υγείας αντιγράφων της κάρτας «Στατιστικά Βάσης» — ορατή σε
  /// ΟΛΟΥΣ (Φάση 7): όσοι δεν χειρίζονται τα αντίγραφα πρέπει τουλάχιστον να
  /// βλέπουν αν οι αλλαγές τους μένουν αφύλακτες.
  static ({String text, bool isWarning}) statsBackupHealth({
    required DatabaseBackupSettings settings,
    required int pendingChanges,
    required bool canManageBackups,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toLocal();

    if (!settings.backupOnExit) {
      return (
        text:
            'Τα αυτόματα αντίγραφα είναι απενεργοποιημένα — για κοινόχρηστη '
            'βάση προτείνεται η ενεργοποίησή τους.',
        isWarning: true,
      );
    }
    if (pendingChanges <= 0) {
      return (
        text: 'Αφύλακτες αλλαγές: καμία — όλα φυλαγμένα.',
        isWarning: false,
      );
    }

    final last = settings.lastAnyBackupAt;
    final overdue =
        last != null &&
        current.difference(last).inMinutes >
            settings.effectiveMaxWaitMinutes + _overdueGraceMinutes;
    if (overdue) {
      return (
        text: canManageBackups
            ? 'Αφύλακτες αλλαγές: $pendingChanges — το αυτόματο αντίγραφο '
                  'έχει καθυστερήσει.'
            : 'Αφύλακτες αλλαγές: $pendingChanges — κανένα πρόσφατο '
                  'αντίγραφο· ενημερώστε τον διαχειριστή.',
        isWarning: true,
      );
    }

    if (!canManageBackups) {
      return (
        text:
            'Αφύλακτες αλλαγές: $pendingChanges — τα αντίγραφα τα χειρίζεται '
            'ο διαχειριστής.',
        isWarning: false,
      );
    }
    if (last == null) {
      return (
        text:
            'Αφύλακτες αλλαγές: $pendingChanges — πρώτο αντίγραφο εντός του '
            'επόμενου λεπτού.',
        isWarning: false,
      );
    }
    final deadline = last.add(
      Duration(minutes: settings.effectiveMaxWaitMinutes),
    );
    return (
      text:
          'Αφύλακτες αλλαγές: $pendingChanges — επόμενο στις '
          '${settings.changeThreshold} αλλαγές ή έως '
          '${formatLocalTimeHm(deadline)}.',
      isWarning: false,
    );
  }

  /// Κατάσταση για το UI: τι εκκρεμεί, πότε έρχεται το επόμενο, τι πήγε
  /// στραβά. Ο μετρητής [pendingChanges] έρχεται από τον καλούντα — ο
  /// υπολογισμός θέλει βάση, η μορφοποίηση όχι.
  static BackupScheduleStatusInfo build({
    required DatabaseBackupSettings settings,
    required int pendingChanges,
    DateTime? now,
    bool backupJobRunning = false,
    String? dbBaseName,
  }) {
    final current = (now ?? DateTime.now()).toLocal();

    if (!settings.backupOnExit) {
      return const BackupScheduleStatusInfo(
        hintText: 'Τα αυτόματα αντίγραφα είναι απενεργοποιημένα.',
      );
    }

    if (settings.destinationDirectory.trim().isEmpty) {
      return const BackupScheduleStatusInfo(
        hintText:
            'Ορίστε φάκελο προορισμού ώστε να εκτελούνται αυτόματα αντίγραφα.',
        hintIsWarning: true,
      );
    }

    String? nextText;
    var imminent = false;

    if (backupJobRunning) {
      nextText = 'Επόμενο αυτόματο αντίγραφο: σε εξέλιξη τώρα…';
    } else {
      final decision = BackupTriggerDecision.evaluate(
        settings: settings,
        pendingChanges: pendingChanges,
        now: current,
      );
      if (decision.due) {
        imminent = true;
        nextText =
            'Επόμενο αυτόματο αντίγραφο: εντός του επόμενου λεπτού '
            '(έλεγχος κάθε λεπτό, όσο η εφαρμογή είναι ανοιχτή).';
      } else {
        switch (decision.reason) {
          case BackupTriggerReason.noPendingChanges:
            nextText = 'Επόμενο αυτόματο αντίγραφο: όταν υπάρξουν αλλαγές.';
          case BackupTriggerReason.spacingNotElapsed:
            final availableAt = settings.lastAnyBackupAt!.add(
              Duration(minutes: settings.minSpacingMinutes),
            );
            nextText =
                'Επόμενο αυτόματο αντίγραφο: όχι πριν τις '
                '${formatLocalTimeHm(availableAt)} (ελάχιστη απόσταση '
                '${settings.minSpacingMinutes}΄).';
          case BackupTriggerReason.belowThreshold:
            final deadline = settings.lastAnyBackupAt!.add(
              Duration(minutes: settings.effectiveMaxWaitMinutes),
            );
            nextText =
                'Επόμενο αυτόματο αντίγραφο: στις '
                '${settings.changeThreshold} αλλαγές, ή το αργότερο στις '
                '${formatLocalTimeHm(deadline)}.';
          default:
            nextText = null;
        }
      }
    }

    String? hintText;
    var hintWarning = false;
    final st = BackupScheduleStatus.normalize(settings.lastBackupStatus);
    if (st == BackupScheduleStatus.folderMissing) {
      hintText =
          'Ο φάκελος προορισμού δεν βρέθηκε· τα αρχεία αντιγράφου μπορεί να λείπουν.';
      hintWarning = true;
    } else if (st == BackupScheduleStatus.failed) {
      hintText =
          'Το τελευταίο αυτόματο αντίγραφο απέτυχε· ελέγξτε φάκελο και δικαιώματα.';
      hintWarning = true;
    }

    var lastText =
        '${pendingChangesLine(pendingChanges)}\n'
        '${_formatLastRecordedAttemptLine(settings, dbBaseName: dbBaseName)}';

    final manual = settings.lastManualBackupAttempt;
    if (manual != null) {
      final base = dbBaseName?.trim() ?? '';
      final scope = base.isEmpty ? '' : ' (βάση «$base»)';
      lastText =
          '$lastText\nΤελευταίο χειροκίνητο αντίγραφο$scope: ${formatLocalDateTime(manual.toLocal())}';
    }

    final lastFull = settings.lastFullBackupAt;
    if (lastFull != null) {
      lastText =
          '$lastText\nΤελευταίο πλήρες αντίγραφο (βάση + φορητά): '
          '${formatLocalDateTime(lastFull.toLocal())}';
    }

    return BackupScheduleStatusInfo(
      nextBackupText: nextText,
      lastBackupText: lastText,
      hintText: hintText,
      hintIsWarning: hintWarning,
      nextIsImminent: imminent,
    );
  }
}
