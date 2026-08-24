import 'package:flutter/material.dart';

import 'draggable_dialog_shell.dart';

/// Ο κοινός διάλογος «κάποιος πρόλαβε», για κάθε εγγραφή που βρήκε διένεξη.
///
/// Εκκρεμότητες, προφίλ και κλήσεις ρωτούν το **ίδιο** πράγμα με διαφορετικά
/// λόγια: ποιος πρόλαβε, τι άγγιξε, τι χάνεται αν γράψω από πάνω. Τρία
/// αντίγραφα του ίδιου παραθύρου θα απέκλιναν στην πρώτη διόρθωση — και η
/// επιλογή «κράτα τη δική μου» πρέπει να συμπεριφέρεται παντού ίδια.
///
/// Επιστρέφει `true` **μόνο** όταν ο χρήστης επιλέξει ρητά να γράψει από πάνω.
/// Το κλείσιμο με Escape δίνει `null` — ισοδύναμο με ακύρωση, ώστε ένα κατά
/// λάθος πάτημα να μη σβήνει ξένη δουλειά.
Future<bool?> showStaleWriteConflictDialog(
  BuildContext context, {
  required String headline,
  required String warning,
  String title = 'Κάποιος πρόλαβε',
  String changedFieldsCaption = 'Τι άγγιξε:',
  List<String> changedFields = const <String>[],
  String keepMineLabel = 'Κράτα τη δική μου',
  String takeTheirsLabel = 'Άφησε τη δική του',

  /// Επιπλέον περιεχόμενο κάτω από τη λίστα — π.χ. το κείμενο της λύσης που
  /// γράφτηκε στο μεταξύ.
  Widget? extra,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _StaleWriteConflictDialog(
      title: title,
      headline: headline,
      warning: warning,
      changedFieldsCaption: changedFieldsCaption,
      changedFields: changedFields,
      keepMineLabel: keepMineLabel,
      takeTheirsLabel: takeTheirsLabel,
      extra: extra,
    ),
  );
}

class _StaleWriteConflictDialog extends StatelessWidget {
  const _StaleWriteConflictDialog({
    required this.title,
    required this.headline,
    required this.warning,
    required this.changedFieldsCaption,
    required this.changedFields,
    required this.keepMineLabel,
    required this.takeTheirsLabel,
    this.extra,
  });

  final String title;
  final String headline;
  final String warning;
  final String changedFieldsCaption;
  final List<String> changedFields;
  final String keepMineLabel;
  final String takeTheirsLabel;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableDialogShell(
      title: Text(title),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        content: SizedBox(
          width: 468,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(headline, style: theme.textTheme.bodyLarge),
                if (changedFields.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    changedFieldsCaption,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final field in changedFields)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 6,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              field,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (extra != null) ...[const SizedBox(height: 12), extra!],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(keepMineLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(takeTheirsLabel),
          ),
        ],
      ),
    );
  }
}
