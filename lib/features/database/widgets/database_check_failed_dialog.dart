import 'package:flutter/material.dart';

import '../../../core/database/database_init_result.dart';
import 'database_newer_recovery_dialog.dart';
import 'schema_upgrade_consent_dialog.dart';

/// Ενιαία απάντηση στο «η βάση δεν πέρασε τον έλεγχο» — ένα σημείο αντί για
/// τρία αντίγραφα του ίδιου διαλόγου.
///
/// Σφάλματα που έχουν πραγματική διέξοδο δρομολογούνται στη ροή ανάκαμψής
/// τους (συγκατάθεση αναβάθμισης, βάση νεότερης έκδοσης)· μόνο ό,τι δεν
/// επιδέχεται ενέργεια καταλήγει σε απλό ενημερωτικό διάλογο.
///
/// Επιστρέφει true όταν μια ροή ανάκαμψης ολοκληρώθηκε επιτυχώς (η βάση
/// άνοιξε), ώστε ο καλών να ανανεώσει ό,τι δείχνει διαδρομές/ετικέτες.
Future<bool> showDatabaseCheckFailedDialog({
  required BuildContext context,
  required DatabaseInitResult result,
  required Future<void> Function() onSuccess,
}) async {
  if (result.recoveryKind == DatabaseInitRecoveryKind.schemaUpgradeConsent) {
    return runSchemaUpgradeConsentRecovery(
      context: context,
      result: result,
      onSuccess: onSuccess,
    );
  }
  if (result.recoveryKind == DatabaseInitRecoveryKind.databaseNewerThanApp) {
    return runDatabaseNewerRecovery(
      context: context,
      result: result,
      onSuccess: onSuccess,
    );
  }

  final msg = result.message ?? 'Η βάση δεν πέρασε τον έλεγχο.';
  final det = result.details?.trim();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Η βάση δεν είναι έγκυρη'),
      content: SingleChildScrollView(
        child: Text(det != null && det.isNotEmpty ? '$msg\n\n$det' : msg),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Εντάξει'),
        ),
      ],
    ),
  );
  return false;
}
