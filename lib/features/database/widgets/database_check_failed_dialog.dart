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

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Η βάση δεν είναι έγκυρη'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: DatabaseCheckFailedContent(result: result),
        ),
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

/// Το περιεχόμενο του διαλόγου, χωριστά ώστε να ελέγχεται χωρίς να στηθεί
/// ολόκληρη ροή επιλογής βάσης.
class DatabaseCheckFailedContent extends StatelessWidget {
  const DatabaseCheckFailedContent({required this.result, super.key});

  final DatabaseInitResult result;

  /// Ετικέτα του πτυσσόμενου τμήματος με το ωμό κείμενο.
  static const String technicalSectionLabel = 'Τεχνικές λεπτομέρειες';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = result.message ?? 'Η βάση δεν πέρασε τον έλεγχο.';
    // Το `details` κουβαλά δύο πράγματα ενωμένα: τη συμβουλή προς τον χρήστη
    // και τα διαγνωστικά. Η συμβουλή μένει ορατή· τα διαγνωστικά είναι τοίχος
    // κειμένου και ανήκουν εκεί που τα ψάχνει όποιος τα χρειάζεται.
    final parts = (result.details?.trim() ?? '').split(
      kDiagnosticsSectionMarker,
    );
    final advice = parts.first.trim();
    final diagnostics = parts.length > 1
        ? parts.sublist(1).join(kDiagnosticsSectionMarker).trim()
        : '';
    final original = result.originalExceptionText?.trim();
    final code = result.technicalCode?.trim();
    final hasTechnical =
        diagnostics.isNotEmpty ||
        (original != null && original.isNotEmpty) ||
        (code != null && code.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(message, style: theme.textTheme.bodyLarge),
        if (advice.isNotEmpty) ...[
          const SizedBox(height: 12),
          SelectableText(
            advice,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        // Το ωμό κείμενο του SQLite είναι συχνά η ΜΟΝΗ πρόταση που λέει τι
        // πραγματικά συνέβη. Δεν μεταφράζεται και δεν ωραιοποιείται· απλώς
        // μπαίνει ένα κλικ μακριά, ώστε να μη γεμίζει την οθόνη όταν δεν
        // χρειάζεται.
        if (hasTechnical) ...[
          const SizedBox(height: 8),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                technicalSectionLabel,
                style: theme.textTheme.labelLarge,
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (diagnostics.isNotEmpty) ...[
                  SelectableText(
                    diagnostics,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (code != null && code.isNotEmpty) ...[
                  SelectableText(
                    'Κωδικός / αναγνωριστικό: $code',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (original != null && original.isNotEmpty) ...[
                  Text(
                    'Αρχικό μήνυμα σφάλματος',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    original,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
