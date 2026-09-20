import 'package:flutter/material.dart';

import '../../../core/config/audit_retention_class.dart';
import '../../../core/services/audit_retention_plan.dart';

/// Δείχνει **τι ακριβώς θα σβηστεί**, πριν σβηστεί.
///
/// **Γιατί όχι σκέτη επιβεβαίωση:** η διαγραφή Ιστορικού είναι οριστική και
/// κοινή για όλους τους σταθμούς. Ένα «θα εφαρμοστούν τα όρια» δεν είναι
/// πληροφορία — ο χειριστής δεν έχει τρόπο να ξέρει αν αυτό σημαίνει δέκα
/// γραμμές ή δέκα χιλιάδες.
///
/// Επιστρέφει `true` μόνο όταν ο χειριστής εγκρίνει ρητά **αυτό** το σχέδιο.
Future<bool> showAuditRetentionPreviewDialog({
  required BuildContext context,
  required AuditRetentionPlan plan,
  required bool exportsBeforePurge,
}) async {
  final approved = await showDialog<bool>(
    context: context,
    // Οριστική διαγραφή: το κλείσιμο με κλικ στο κενό δεν είναι απάντηση.
    barrierDismissible: false,
    builder: (context) {
      final theme = Theme.of(context);

      Widget line(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      );

      return AlertDialog(
        icon: Icon(Icons.delete_sweep_outlined, color: theme.colorScheme.error),
        title: const Text('Τι θα σβηστεί από το Ιστορικό'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Το Ιστορικό είναι κοινό: ό,τι σβηστεί φεύγει οριστικά για '
                  'όλους τους σταθμούς.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),

                for (final classPlan in plan.classPlans)
                  if (classPlan.totalRows > 0)
                    line(
                      auditRetentionClassLabel(classPlan.retentionClass),
                      classPlan.retentionClass == AuditRetentionClass.permanent
                          ? 'δεν αγγίζονται (${classPlan.totalRows})'
                          : '−${classPlan.rowsToDelete} από '
                                '${classPlan.totalRows}',
                      color: classPlan.rowsToDelete > 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),

                if (plan.trimRows > 0)
                  line(
                    'Επιπλέον, από το όριο πλήθους',
                    '−${plan.trimRows}',
                    color: theme.colorScheme.error,
                  ),

                const Divider(height: 22),
                line(
                  'Σβήνονται συνολικά',
                  '${plan.totalRowsToDelete}',
                  color: theme.colorScheme.error,
                ),
                line('Μένουν', '${plan.rowsRemaining}'),

                if (plan.rowsToCompact > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Επιπλέον, ${plan.rowsToCompact} εγγραφές θα πετάξουν το '
                    'βοηθητικό κείμενο αναζήτησής τους. Καμία από αυτές δεν '
                    'σβήνεται — γίνονται μόνο πιο δύσκολα αναζητήσιμες, και '
                    'το κείμενο ξαναφτιάχνεται όποτε θελήσετε.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],

                if (plan.limitReason ==
                    AuditRetentionLimitReason.floorReached) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Μέρος της διαγραφής δεν θα γίνει: τα όρια που ορίσατε θα '
                    'άδειαζαν το Ιστορικό κάτω από το ελάχιστο που κρατά '
                    'πάντα η εφαρμογή.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],

                if (exportsBeforePurge && plan.totalRowsToDelete > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.save_alt_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Πριν σβηστούν, θα γραφτούν σε αρχείο δίπλα στη '
                          'βάση — αν αποδειχθεί ότι τις χρειαζόσασταν.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: Text('Σβήσε ${plan.totalRowsToDelete}'),
          ),
        ],
      );
    },
  );
  return approved == true;
}
