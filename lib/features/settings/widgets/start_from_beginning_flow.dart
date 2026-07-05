import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/services/application_reset_service.dart';
import '../../../core/services/backup_reset_metadata.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../../features/calls/provider/call_entry_provider.dart';
import '../../../features/calls/provider/call_header_provider.dart';
import '../../../features/database/providers/backup_scheduler_provider.dart';

/// True όταν υπάρχει ενεργή ή μη αποθηκευμένη καταγραφή κλήσης.
bool hasOpenCallSession(
  CallEntryState entry,
  SmartEntitySelectorState header,
) {
  if (entry.isCallTimerRunning || entry.retainPlayPauseAfterManualZero) {
    return true;
  }
  if (entry.durationSeconds > 0) return true;
  if (entry.isPending) return true;
  if (entry.notes.trim().isNotEmpty) return true;
  if (header.selectedPhone?.trim().isNotEmpty == true) return true;
  if (header.callerDisplayText.trim().isNotEmpty) return true;
  if (header.departmentText.trim().isNotEmpty) return true;
  if (header.equipmentText.trim().isNotEmpty) return true;
  if (header.selectedCaller != null) return true;
  if (header.selectedEquipment != null) return true;
  return false;
}

/// Ροή «Ξεκίνα από την αρχή» από τις Γενικές ρυθμίσεις.
class StartFromBeginningFlow {
  StartFromBeginningFlow._();

  static void _returnToCallsScreen(BuildContext context, WidgetRef ref) {
    ref.read(mainNavRequestProvider.notifier).request(
          const MainNavRequest(destination: MainNavDestination.calls),
        );
    Navigator.of(context).pop();
  }

  static Future<void> run(BuildContext context, WidgetRef ref) async {
    final callState = ref.read(callEntryProvider);
    final headerState = ref.read(callHeaderProvider);
    if (hasOpenCallSession(callState, headerState)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ανοιχτή κλήση'),
          content: const Text(
            'Υπάρχει ενεργή ή μη αποθηκευμένη καταγραφή κλήσης. '
            'Η επαναφορά θα την αγνοήσει.\n\n'
            'Θέλετε να επιστρέψετε στην κλήση ή να συνεχίσετε την επαναφορά;',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(false);
                _returnToCallsScreen(context, ref);
              },
              child: const Text('Επιστροφή στην κλήση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Συνέχεια επαναφοράς'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (proceed != true) return;
    }

    if (ref.read(backupSchedulerProvider.notifier).isBackupJobRunning) {
      final skip = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Αντίγραφο ασφαλείας σε εξέλιξη'),
          content: const Text(
            'Τρέχει αυτόματο αντίγραφο ασφαλείας. '
            'Η διακοπή μπορεί να αφήσει ημιτελές αρχείο.\n\n'
            'Θέλετε να περιμένετε ή να συνεχίσετε με παράβλεψη;',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Ακύρωση'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Παράβλεψη'),
            ),
          ],
        ),
      );
      if (skip != true || !context.mounted) return;
    }

    final backupMeta = await BackupResetMetadataReader.read(ref: ref);
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ξεκίνα από την αρχή'),
        content: SingleChildScrollView(
          child: _ResetWarningBody(backupMeta: backupMeta),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Συνέχεια'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Κλείσιμο οθόνης ρυθμίσεων — η οθόνη επαναφοράς είναι στο AppInitWrapper.
    Navigator.of(context).pop();

    ref.read(callEntryProvider.notifier).reset();
    await ApplicationResetService.instance.beginPendingReset();
    if (!context.mounted) return;
    ApplicationResetService.instance.invalidateAfterResetLifecycle(ref);
  }
}

class _ResetWarningBody extends StatelessWidget {
  const _ResetWarningBody({required this.backupMeta});

  final BackupResetMetadata backupMeta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Αποσυνδέεστε από τα παρακάτω δεδομένα (δεν διαγράφονται από το δίσκο):',
          style: bodyStyle?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ...const [
          'Χρήστες, τμήματα, εξοπλισμός και κατάλογος',
          'Χάρτες κτιρίου (δεν θα φαίνονται μέχρι σύνδεση σε σχετική βάση)',
          'Παλιά βάση Λάμπα — διαδρομές και ρυθμίσεις (όχι τα αρχεία .db)',
          'Απομακρυσμένα εργαλεία, Lansweeper, ρυθμίσεις απομακρυσμένης σύνδεσης',
          'Εκκρεμότητες, ιστορικό κλήσεων, καταγραφές audit',
          'Ορθογραφία και λεξικό',
          'Παλέτα χρωμάτων τμημάτων',
          'Όλες οι τοπικές ρυθμίσεις εφαρμογής (σαν πρώτη εκτέλεση)',
        ].map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• '),
                Expanded(child: Text(line, style: bodyStyle)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Σε κοινόχρηστη (δικτυακή) βάση, οι άλλοι χρήστες συνεχίζουν κανονικά — '
          'επηρεάζεται μόνο αυτή η εγκατάσταση.',
          style: bodyStyle,
        ),
        const SizedBox(height: 12),
        Text(
          'Τα αρχεία .db στο δίσκο δεν διαγράφονται. '
          'Αν ξαναεπιλέξετε την ίδια βάση, όλα τα δεδομένα θα επανέλθουν. '
          'Μπορείτε να δημιουργήσετε νέα κενή βάση στον ίδιο φάκελο '
          '(π.χ. call_logger_reset.db) και να εναλλάσσεστε ανάμεσα σε αρχεία.',
          style: bodyStyle,
        ),
        if (backupMeta.hasBackupFolder) ...[
          const SizedBox(height: 12),
          Text(
            backupMeta.latestBackupLabel == null
                ? 'Διατηρούνται αντίγραφα ασφαλείας στο φάκελο: '
                    '${backupMeta.destinationFolderName}.'
                : 'Διατηρούνται αντίγραφα ασφαλείας στο φάκελο: '
                    '${backupMeta.destinationFolderName} — πιο πρόσφατο: '
                    '${backupMeta.latestBackupLabel}.',
            style: bodyStyle,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Η επαναφορά από zip γίνεται ξεχωριστά από τον πίνακα βάσης δεδομένων.',
          style: bodyStyle?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
