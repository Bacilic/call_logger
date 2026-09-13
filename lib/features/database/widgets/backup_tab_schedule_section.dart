import 'package:flutter/material.dart';

import '../models/database_backup_settings.dart';
import '../utils/backup_destination_folder_validator.dart';
import '../utils/backup_schedule_status.dart';
import 'backup_int_setting_field.dart';

/// «Πότε παίρνεται»: τα τρία όρια πυροδότησης και το αντίγραφο κλεισίματος.
class BackupTabTriggerSection extends StatelessWidget {
  const BackupTabTriggerSection({
    super.key,
    required this.settings,
    required this.thresholdController,
    required this.thresholdFocus,
    required this.onPersistThreshold,
    required this.minSpacingController,
    required this.minSpacingFocus,
    required this.onPersistMinSpacing,
    required this.maxWaitController,
    required this.maxWaitFocus,
    required this.onPersistMaxWait,
    required this.onToggleBackupOnClose,
  });

  final DatabaseBackupSettings settings;
  final TextEditingController thresholdController;
  final FocusNode thresholdFocus;
  final Future<void> Function() onPersistThreshold;
  final TextEditingController minSpacingController;
  final FocusNode minSpacingFocus;
  final Future<void> Function() onPersistMinSpacing;
  final TextEditingController maxWaitController;
  final FocusNode maxWaitFocus;
  final Future<void> Function() onPersistMaxWait;
  final ValueChanged<bool> onToggleBackupOnClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Πότε παίρνεται',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Το αντίγραφο πυροδοτείται από τις αλλαγές — μετρούν και οι '
          'αλλαγές των συναδέλφων στην κοινόχρηστη βάση. Χωρίς καμία '
          'αλλαγή δεν παίρνεται ποτέ αντίγραφο.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        BackupIntSettingField(
          leadingText: 'Κάθε ',
          trailingText: ' αλλαγές',
          controller: thresholdController,
          focusNode: thresholdFocus,
          min: 1,
          max: 9999,
          onPersist: onPersistThreshold,
        ),
        BackupIntSettingField(
          leadingText: 'Το συντομότερο μετά από ',
          trailingText: ' λεπτά',
          controller: minSpacingController,
          focusNode: minSpacingFocus,
          min: DatabaseBackupSettings.minAllowedSpacingMinutes,
          max: 1440,
          limitHint:
              'ελάχιστο '
              '${DatabaseBackupSettings.minAllowedSpacingMinutes} λεπτά',
          limitTooltip:
              'Κάθε αντίγραφο διαβάζει ολόκληρη τη βάση μέσα από το '
              'δίκτυο· πιο συχνά από αυτό, η δουλειά σας θα το νιώθει.',
          onPersist: onPersistMinSpacing,
        ),
        BackupIntSettingField(
          leadingText: 'Το αργότερο μετά από ',
          trailingText: ' λεπτά',
          controller: maxWaitController,
          focusNode: maxWaitFocus,
          min: DatabaseBackupSettings.minAllowedSpacingMinutes,
          max: 10080,
          onPersist: onPersistMaxWait,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Και στο κλείσιμο της εφαρμογής, αν υπάρχουν αφύλακτες αλλαγές',
          ),
          value: settings.backupOnCloseIfPending,
          onChanged: onToggleBackupOnClose,
        ),
      ],
    );
  }
}

/// Οι γραμμές κατάστασης: πότε είναι το επόμενο, πότε ήταν το τελευταίο, τι
/// δείχνει ο φάκελος προορισμού.
class BackupTabScheduleStatus extends StatelessWidget {
  const BackupTabScheduleStatus({
    super.key,
    required this.settings,
    required this.pendingChanges,
    required this.jobRunning,
    required this.destinationContentFuture,
    this.databaseBaseName,
  });

  final DatabaseBackupSettings settings;
  final int pendingChanges;
  final bool jobRunning;
  final Future<BackupDestinationContentResult> destinationContentFuture;
  final String? databaseBaseName;

  @override
  Widget build(BuildContext context) {
    final status = BackupScheduleStatusFormatter.build(
      settings: settings,
      pendingChanges: pendingChanges,
      backupJobRunning: jobRunning,
      dbBaseName: databaseBaseName,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status.nextBackupText != null)
            _StatusLine(
              text: status.nextBackupText!,
              emphasize: status.nextIsImminent,
            ),
          if (status.lastBackupText != null)
            ...status.lastBackupText!
                .split('\n')
                .map((row) => _StatusLine(text: row)),
          FutureBuilder<BackupDestinationContentResult>(
            future: destinationContentFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const _StatusLine(text: 'Έλεγχος φακέλου…');
              }
              final content = snapshot.data!;
              return _StatusLine(
                text: BackupScheduleStatusFormatter.destinationContentLabelEl(
                  content,
                ),
                warning:
                    content.kind == BackupDestinationContentKind.folderMissing,
                // Η κενή διαδρομή είναι διαπίστωση, όχι συναγερμός: το κόκκινο
                // «Ορίστε φάκελο προορισμού…» από κάτω κουβαλά ήδη την
                // επείγουσα οδηγία, και δύο κόκκινες γραμμές για το ίδιο
                // πράγμα θα αλληλοακυρώνονταν.
                caution:
                    content.kind ==
                        BackupDestinationContentKind.folderEmptyNoFiles ||
                    content.kind == BackupDestinationContentKind.folderNotSet,
              );
            },
          ),
          if (status.hintText != null)
            _StatusLine(text: status.hintText!, warning: status.hintIsWarning),
        ],
      ),
    );
  }
}

/// Μία γραμμή κατάστασης, χρωματισμένη κατά τη σοβαρότητά της.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.text,
    this.warning = false,
    this.caution = false,
    this.emphasize = false,
  });

  final String text;
  final bool warning;
  final bool caution;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warning
        ? theme.colorScheme.error
        : caution
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: emphasize ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}
