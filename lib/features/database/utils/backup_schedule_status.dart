import 'package:intl/intl.dart';

import '../models/database_backup_settings.dart';
import 'backup_destination_folder_validator.dart';
import 'backup_schedule_utils.dart';

/// Πληροφορίες εμφάνισης για επόμενο/τελευταίο προγραμματισμένο αντίγραφο.
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

/// Υπολογισμός και μορφοποίηση κατάστασης προγράμματος backup για το UI.
abstract final class BackupScheduleStatusFormatter {
  BackupScheduleStatusFormatter._();

  static const _weekdayShort = [
    'Δευ',
    'Τρι',
    'Τετ',
    'Πεμ',
    'Παρ',
    'Σαβ',
    'Κυρ',
  ];

  static String formatLocalTimeHm(DateTime local) {
    final l = local.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final min = l.minute.toString().padLeft(2, '0');
    return '$hh:$min';
  }

  static bool hasManualBackupToday(
    DatabaseBackupSettings settings,
    DateTime now,
  ) {
    final manual = settings.lastManualBackupAttempt;
    return manual != null &&
        BackupScheduleUtils.isSameLocalDate(manual.toLocal(), now.toLocal());
  }

  /// True όταν έχει ήδη εκτελεστεί προγραμματισμένο αντίγραφο σήμερα (ένα ανά ημέρα).
  static bool hasScheduledBackupToday(
    DatabaseBackupSettings settings,
    DateTime now,
  ) {
    final attempt = settings.lastBackupAttempt;
    return attempt != null &&
        BackupScheduleUtils.isSameLocalDate(attempt.toLocal(), now.toLocal());
  }

  static DateTime? _scheduleSlotForDay(DateTime day, String time) {
    final p = BackupScheduleUtils.parseTime(time);
    if (p == null) return null;
    final d = day.toLocal();
    return DateTime(d.year, d.month, d.day, p.hour, p.minute);
  }

  /// Αν δεν πρέπει να σημειωθεί/να εμφανιστεί «χάθηκε» για το τρέχον πρόγραμμα.
  ///
  /// Ικανοποιημένο: χειροκίνητο σήμερα, επιτυχές προγραμματισμένο σήμερα, ή
  /// προσπάθεια σήμερα μετά/στην προγραμματισμένη ώρα.
  static bool isScheduleSatisfiedForToday(
    DatabaseBackupSettings settings,
    DateTime now,
  ) {
    final local = now.toLocal();
    if (hasManualBackupToday(settings, local)) return true;

    final attempt = settings.lastBackupAttempt;
    if (attempt == null ||
        !BackupScheduleUtils.isSameLocalDate(attempt.toLocal(), local)) {
      return false;
    }

    final status = BackupScheduleStatus.normalize(settings.lastBackupStatus);
    if (status == BackupScheduleStatus.success) return true;

    final slot = _scheduleSlotForDay(local, settings.backupTime);
    if (slot == null) return false;
    return !attempt.toLocal().isBefore(slot);
  }

  /// True όταν πρέπει να τρέξει fallback αντίγραφο κατά το κλείσιμο (Windows).
  ///
  /// Απαιτεί προγραμματισμένη ημέρα, ώρα που έχει περάσει και εκκρεμές αντίγραφο
  /// (αποτυχία, χάθηκε ή καμία επιτυχής προσπάθεια σήμερα).
  static bool shouldRunExitBackup(
    DatabaseBackupSettings settings,
    DateTime now,
  ) {
    if (!settings.backupOnExit || !settings.usesCustomSchedule) return false;
    if (settings.destinationDirectory.trim().isEmpty) return false;

    final local = now.toLocal();
    if (!BackupScheduleUtils.isScheduledWeekday(local, settings.backupDays)) {
      return false;
    }
    if (!BackupScheduleUtils.hasReachedTimeToday(local, settings.backupTime)) {
      return false;
    }
    if (hasManualBackupToday(settings, local)) return false;

    final status = BackupScheduleStatus.normalize(settings.lastBackupStatus);
    if (hasScheduledBackupToday(settings, local) &&
        status == BackupScheduleStatus.success) {
      return false;
    }
    return true;
  }

  /// True μόνο σε προγραμματισμένη ημέρα, μετά την ώρα, όταν λείπει αντίγραφο σήμερα.
  static bool shouldMarkScheduleMissed(
    DatabaseBackupSettings settings,
    DateTime now,
  ) {
    if (!settings.backupOnExit || !settings.usesCustomSchedule) return false;
    if (settings.destinationDirectory.trim().isEmpty) return false;

    final local = now.toLocal();
    if (!BackupScheduleUtils.isScheduledWeekday(local, settings.backupDays)) {
      return false;
    }
    if (!BackupScheduleUtils.hasReachedTimeToday(local, settings.backupTime)) {
      return false;
    }
    if (isScheduleSatisfiedForToday(settings, local)) return false;
    if (BackupScheduleStatus.normalize(settings.lastBackupStatus) ==
        BackupScheduleStatus.failed) {
      return false;
    }
    return true;
  }

  /// True όταν πρέπει να εμφανιστεί διάλογος «χάθηκε» (ίδιοι κανόνες με [shouldMarkScheduleMissed]).
  static bool shouldShowBackupMissedAlert(
    DatabaseBackupSettings settings,
    DateTime now,
  ) =>
      shouldMarkScheduleMissed(settings, now);

  static String formatLocalDateTime(DateTime local) {
    final w = _weekdayShort[local.weekday - 1];
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yyyy = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$w $dd-$mm-$yyyy $hh:$min';
  }

  static String _formatLastRecordedAttemptLine(
    DatabaseBackupSettings settings,
  ) {
    final last = settings.lastBackupAttempt;
    if (last == null) {
      return 'Τελευταία καταγεγραμμένη προσπάθεια: καμία καταγραφή.';
    }

    final datePart = formatLocalDateTime(last.toLocal());
    const prefix = 'Τελευταία καταγεγραμμένη προσπάθεια:';

    switch (BackupScheduleStatus.normalize(settings.lastBackupStatus)) {
      case BackupScheduleStatus.success:
        return '$prefix $datePart — επιτυχία';
      case BackupScheduleStatus.failed:
        return '$prefix $datePart — αποτυχία';
      case BackupScheduleStatus.missed:
        return '$prefix $datePart — χάθηκε';
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
    switch (content.kind) {
      case BackupDestinationContentKind.folderMissing:
        return 'ο φάκελος προορισμού δεν υπάρχει';
      case BackupDestinationContentKind.folderEmptyNoFiles:
        return 'ο φάκελος υπάρχει αλλά δεν βρέθηκαν αρχεία αντιγράφου';
      case BackupDestinationContentKind.folderOk:
        final n = content.matchingBackupFileCount;
        final latest = content.latestBackupModified;
        final countPart = n == 1 ? '1 αρχείο' : '$n αρχεία';
        if (latest == null) {
          return n == 1
              ? 'Βρέθηκε $countPart'
              : 'Βρέθηκαν $countPart';
        }
        final stamp = DateFormat('dd/MM/yyyy HH:mm').format(latest.toLocal());
        return n == 1
            ? 'Βρέθηκε $countPart με πιο πρόσφατο στις $stamp'
            : 'Βρέθηκαν $countPart με πιο πρόσφατο στις $stamp';
    }
  }

  /// Επόμενη χρονική στιγμή προγράμματος (από [now], αποκλείοντας σημερινό slot αν έχει ήδη τρέξει).
  static DateTime? nextScheduleInstant(
    DateTime now,
    List<int> weekdays,
    String time, {
    DateTime? lastBackupAttempt,
  }) {
    final p = BackupScheduleUtils.parseTime(time);
    if (p == null || weekdays.isEmpty) return null;

    final todayStart = DateTime(now.year, now.month, now.day);
    final attemptedToday = lastBackupAttempt != null &&
        BackupScheduleUtils.isSameLocalDate(lastBackupAttempt, now);

    for (var dayOffset = 0; dayOffset <= 14; dayOffset++) {
      final day = todayStart.add(Duration(days: dayOffset));
      if (!weekdays.contains(day.weekday)) continue;

      final slot = DateTime(day.year, day.month, day.day, p.hour, p.minute);
      if (dayOffset == 0) {
        if (attemptedToday) continue;
        if (slot.isAfter(now)) return slot;
        // Ώρα έχει περάσει σήμερα· ο scheduler θα τρέξει στο επόμενο tick (αντί για null).
        return slot;
      }
      return slot;
    }
    return null;
  }

  static bool isNextBackupImminent(
    DateTime now,
    List<int> weekdays,
    String time, {
    DateTime? lastBackupAttempt,
  }) {
    if (!weekdays.contains(now.weekday)) return false;
    if (lastBackupAttempt != null &&
        BackupScheduleUtils.isSameLocalDate(lastBackupAttempt, now)) {
      return false;
    }
    final p = BackupScheduleUtils.parseTime(time);
    if (p == null) return false;
    final slot = DateTime(now.year, now.month, now.day, p.hour, p.minute);
    return !slot.isAfter(now);
  }

  static BackupScheduleStatusInfo build({
    required DatabaseBackupSettings settings,
    DateTime? now,
    bool backupJobRunning = false,
  }) {
    final current = (now ?? DateTime.now()).toLocal();

    if (!settings.backupOnExit) {
      return const BackupScheduleStatusInfo(
        hintText:
            'Τα αυτόματα αντίγραφα είναι απενεργοποιημένα.',
      );
    }

    if (!settings.usesCustomSchedule) {
      return const BackupScheduleStatusInfo(
        hintText:
            'Ορίστε τουλάχιστον μία ημέρα και έγκυρη ώρα για προγραμματισμένο αντίγραφο.',
        hintIsWarning: true,
      );
    }

    if (settings.destinationDirectory.trim().isEmpty) {
      return const BackupScheduleStatusInfo(
        hintText:
            'Ορίστε φάκελο προορισμού ώστε να εκτελεστεί το προγραμματισμένο αντίγραφο.',
        hintIsWarning: true,
      );
    }

    String? nextText;
    String? hintText;
    var hintWarning = false;
    var imminent = false;

    if (backupJobRunning) {
      nextText = 'Επόμενο αυτόματο αντίγραφο: σε εξέλιξη τώρα…';
    } else {
      imminent = isNextBackupImminent(
        current,
        settings.backupDays,
        settings.backupTime,
        lastBackupAttempt: settings.lastBackupAttempt,
      );
      final next = nextScheduleInstant(
        current,
        settings.backupDays,
        settings.backupTime,
        lastBackupAttempt: settings.lastBackupAttempt,
      );

      if (next != null) {
        if (imminent) {
          nextText =
              'Επόμενο αυτόματο αντίγραφο: εντός του επόμενου λεπτού '
              '(έλεγχος κάθε λεπτό, όσο η εφαρμογή είναι ανοιχτή).';
        } else {
          nextText =
              'Επόμενο αυτόματο αντίγραφο: ${formatLocalDateTime(next)}';
        }
      }

      final attemptedToday = settings.lastBackupAttempt != null &&
          BackupScheduleUtils.isSameLocalDate(settings.lastBackupAttempt!, current);
      final atWindow = BackupScheduleUtils.isScheduledWeekday(
            current,
            settings.backupDays,
          ) &&
          BackupScheduleUtils.hasReachedTimeToday(current, settings.backupTime);

      if (attemptedToday && atWindow) {
        hintText =
            'Σήμερα έχει ήδη εκτελεστεί προγραμματισμένο αντίγραφο· '
            'νέα ώρα ή επανεπιλογή ημέρας ισχύει από την επόμενη προγραμματισμένη ημέρα.';
        hintWarning = true;
      } else if (settings.lastBackupStatus == BackupScheduleStatus.missed) {
        hintText =
            'Το τελευταίο προγραμματισμένο αντίγραφο χάθηκε (η εφαρμογή δεν ήταν ανοιχτή στη σχετική ώρα).';
        hintWarning = true;
      } else if (settings.lastBackupStatus ==
          BackupScheduleStatus.folderMissing) {
        hintText =
            'Ο φάκελος προορισμού δεν βρέθηκε· τα αρχεία αντιγράφου μπορεί να λείπουν.';
        hintWarning = true;
      } else if (settings.lastBackupStatus == BackupScheduleStatus.failed) {
        hintText =
            'Το τελευταίο προγραμματισμένο αντίγραφο απέτυχε· ελέγξτε φάκελο και δικαιώματα.';
        hintWarning = true;
      }
    }

    var lastText = _formatLastRecordedAttemptLine(settings);

    final manual = settings.lastManualBackupAttempt;
    if (manual != null) {
      lastText =
          '$lastText\nΤελευταίο χειροκίνητο αντίγραφο: ${formatLocalDateTime(manual.toLocal())}';
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
