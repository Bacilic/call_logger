import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_check_result.dart';
import 'update_installer_service.dart';
import 'update_manifest.dart';
import 'update_providers.dart';

/// Διάλογος «Διαθέσιμη νέα έκδοση» → προαιρετική προετοιμασία ενημέρωσης.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  UpdateCheckResult result,
) async {
  final manifest = result.manifest;
  if (manifest == null) return;

  final choice = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Διαθέσιμη νέα έκδοση'),
      content: Text(
        'Διαθέσιμη νέα έκδοση ${manifest.version} '
        '(${manifest.released}) — θέλετε να την προετοιμάσετε τώρα;',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Αργότερα'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Ενημέρωση'),
        ),
      ],
    ),
  );

  if (choice != true || !context.mounted) return;
  await runUpdatePrepareFlow(context, manifest);
}

/// Προετοιμάζει την ενημέρωση (χωρίς κλείσιμο) και μετά ρωτά για επανεκκίνηση:
/// «Τώρα» → άμεση εφαρμογή· «Αργότερα» → εφαρμογή στο επόμενο άνοιγμα.
///
/// Χρησιμοποιεί [ProviderScope.containerOf] αντί για [WidgetRef], ώστε η ροή
/// να παραμένει ασφαλής ακόμα κι αν ο διάλογος που την ξεκίνησε έχει ήδη
/// κλείσει (π.χ. Ιστορικό Αλλαγών → pop → prepare).
Future<void> runUpdatePrepareFlow(
  BuildContext context,
  UpdateManifest manifest,
) async {
  final container = ProviderScope.containerOf(context);
  final progress = ValueNotifier<String>('Προετοιμασία…');

  // Fire-and-forget σκόπιμα: ο διάλογος προόδου μπαίνει σύγχρονα στο navigator
  // stack και κλείνει παρακάτω με pop. ΜΗΝ γίνει await (θα κρέμαγε — το future
  // ολοκληρώνεται μόνο στο κλείσιμο, που κάνει ο ίδιος ο επόμενος κώδικας).
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Προετοιμασία ενημέρωσης'),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, message, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    ),
  ));

  late UpdateInstallResult result;
  try {
    result = await prepareAvailableUpdate(
      container.read(updateInstallerServiceProvider),
      manifest: manifest,
      onProgress: (msg) => progress.value = msg,
    );
  } finally {
    progress.dispose();
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // κλείσιμο προόδου

  if (!result.success) {
    await _showFailure(context, result);
    return;
  }

  // Το UI (π.χ. κουμπί Ιστορικού) ενημερώνεται ότι υπάρχει εκκρεμότητα.
  container.invalidate(pendingUpdateProvider);

  final restartNow = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Η ενημέρωση είναι έτοιμη'),
      content: Text(
        'Η έκδοση ${manifest.version} είναι έτοιμη για εγκατάσταση.\n'
        'Θέλετε επανεκκίνηση τώρα; Αν επιλέξετε «Αργότερα», η ενημέρωση '
        'θα εφαρμοστεί αυτόματα την επόμενη φορά που θα ανοίξετε την εφαρμογή.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Αργότερα'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Επανεκκίνηση τώρα'),
        ),
      ],
    ),
  );

  if (restartNow == true && context.mounted) {
    await launchPendingUpdateNow(context);
  }
}

/// Εκκινεί άμεσα την εκκρεμή ενημέρωση (κλείσιμο + updater + επανεκκίνηση).
Future<void> launchPendingUpdateNow(BuildContext context) async {
  final container = ProviderScope.containerOf(context);

  // Fire-and-forget σκόπιμα (βλ. σχόλιο στο runUpdatePrepareFlow).
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Επανεκκίνηση'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            LinearProgressIndicator(),
            SizedBox(height: 16),
            Text('Η εφαρμογή θα κλείσει και θα ανοίξει ξανά αυτόματα…'),
          ],
        ),
      ),
    ),
  ));

  // Δώσε ένα frame στο framework να ζωγραφίσει τον διάλογο ΠΡΙΝ ξεκινήσει η
  // ακολουθία τερματισμού (launchPendingUpdate → exit), αλλιώς ο διάλογος
  // μπορεί να μη φανεί καθόλου πριν κλείσει η εφαρμογή.
  await WidgetsBinding.instance.endOfFrame;

  final result = await container
      .read(updateInstallerServiceProvider)
      .launchPendingUpdate();

  if (!context.mounted) return;
  // Σε επιτυχία το terminateApp κλείνει τη διεργασία· αν φτάσουμε εδώ,
  // είτε απέτυχε η εκκίνηση είτε ο τερματιστής δεν έκλεισε ακόμα.
  Navigator.of(context, rootNavigator: true).pop();

  if (!result.success) {
    await _showFailure(context, result);
  }
}

Future<void> _showFailure(
  BuildContext context,
  UpdateInstallResult result,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Αποτυχία ενημέρωσης'),
      content: Text(
        result.failedStep == null
            ? (result.message ?? 'Άγνωστο σφάλμα')
            : 'Στο βήμα «${result.failedStep}»: ${result.message ?? ''}',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Εντάξει'),
        ),
      ],
    ),
  );
}
