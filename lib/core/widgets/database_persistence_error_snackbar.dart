import 'package:flutter/material.dart';

import '../database/database_init_result.dart';

/// SnackBar + προαιρετικός διάλογος αναφοράς για αποτυχία εγγραφής/ανάγνωσης SQLite.
void showDatabasePersistenceErrorSnackBar(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
) {
  final result = DatabaseInitResult.fromException(error, null, stackTrace);
  final scheme = Theme.of(context).colorScheme;
  final summary =
      (result.message ?? 'Αποτυχία εγγραφής στη βάση δεδομένων.').trim();
  final details = result.details?.trim();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: TextStyle(
              color: scheme.onError,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (details != null && details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details,
              style: TextStyle(
                color: scheme.onError.withValues(alpha: 0.92),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
      backgroundColor: scheme.error,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 12),
      action: SnackBarAction(
        textColor: scheme.onError,
        label: 'Αναφορά',
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Λεπτομέρειες σφάλματος'),
              content: SingleChildScrollView(
                child: SelectableText(
                  result.buildClipboardReport(),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Κλείσιμο'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
