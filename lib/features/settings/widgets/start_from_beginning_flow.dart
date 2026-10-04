import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_permission.dart';
import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/services/application_reset_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/widgets/main_nav_destination.dart';
import '../../../features/calls/provider/call_entry_provider.dart';
import '../../../features/calls/provider/call_header_provider.dart';
import '../../../features/database/providers/backup_scheduler_provider.dart';

/// True όταν υπάρχει ενεργή ή μη αποθηκευμένη καταγραφή κλήσης.
bool hasOpenCallSession(CallEntryState entry, SmartEntitySelectorState header) {
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

/// Η ενότητα «Επαναφορά εφαρμογής» των Ρυθμίσεων — επικεφαλίδα και κουμπί.
///
/// Χωρίς το δικαίωμα [AppPermission.resetApplication] **δεν υπάρχει καθόλου**,
/// ούτε η επικεφαλίδα: γκρίζο κουμπί θα ήταν πρόσκληση να ρωτήσει κανείς
/// «γιατί δεν μπορώ», όπως στο Ιστορικό Εφαρμογής.
class ApplicationResetSection extends ConsumerWidget {
  const ApplicationResetSection({super.key, this.enabled = true});

  /// `false` όσο φορτώνουν ακόμη οι ρυθμίσεις της οθόνης.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!PermissionService.instance.can(AppPermission.resetApplication)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Επαναφορά εφαρμογής',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.restart_alt, color: theme.colorScheme.error),
          title: const Text('Ξεκίνα από την αρχή (Επαναφορά ρυθμίσεων)'),
          subtitle: const Text(
            'Ο υπολογιστής ξεχνά τη βάση και τις ρυθμίσεις του και ξεκινά σαν '
            'πρώτη φορά. Δεν σβήνεται τίποτα από τη βάση.',
          ),
          onTap: enabled
              ? () => StartFromBeginningFlow.run(context, ref)
              : null,
        ),
      ],
    );
  }
}

/// Ροή «Ξεκίνα από την αρχή» από τις Γενικές ρυθμίσεις.
class StartFromBeginningFlow {
  StartFromBeginningFlow._();

  static void _returnToCallsScreen(BuildContext context, WidgetRef ref) {
    ref
        .read(mainNavRequestProvider.notifier)
        .request(const MainNavRequest(destination: MainNavDestination.calls));
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

    final databasePath = await SettingsService().getDatabasePath();
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ξεκίνα από την αρχή'),
        content: SingleChildScrollView(
          child: _ResetWarningBody(databasePath: databasePath),
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
  const _ResetWarningBody({required this.databasePath});

  /// Η βάση από την οποία αποσυνδέεται ο υπολογιστής — χωρίς αυτήν, όποιος
  /// δεν ξέρει τη δικτυακή διαδρομή δεν μπορεί να ξανασυνδεθεί.
  final String databasePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.45);
    final headingStyle = bodyStyle?.copyWith(fontWeight: FontWeight.w600);

    Widget bullet(String line) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(line, style: bodyStyle)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Τι θα γίνει σε αυτόν τον υπολογιστή:', style: headingStyle),
        const SizedBox(height: 8),
        bullet(
          'Αποσυνδέεται από τη βάση και σας ζητά αμέσως να διαλέξετε βάση· '
          'εκεί μπορείτε ακόμη να πατήσετε «Ακύρωση» και να γυρίσουν όλα '
          'όπως ήταν.',
        ),
        bullet(
          'Οι ρυθμίσεις που κρατά αυτός ο υπολογιστής γυρίζουν στις αρχικές, '
          'σαν πρώτη εγκατάσταση.',
        ),
        const SizedBox(height: 12),
        Text('Τι ΔΕΝ αλλάζει:', style: headingStyle),
        const SizedBox(height: 8),
        bullet(
          'Δεν σβήνεται τίποτα. Κλήσεις, Κατάλογος, εκκρεμότητες, ιστορικό και '
          'οι ρυθμίσεις που ζουν στη βάση μένουν όπως είναι.',
        ),
        bullet('Οι άλλοι υπολογιστές συνεχίζουν κανονικά.'),
        const SizedBox(height: 12),
        Text(
          'Σημειώστε πού βρίσκεται η βάση — θα τη χρειαστείτε για να '
          'ξανασυνδεθείτε:',
          style: bodyStyle,
        ),
        const SizedBox(height: 4),
        SelectableText(databasePath, style: headingStyle),
      ],
    );
  }
}
