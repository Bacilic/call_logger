import 'package:flutter/material.dart';

import '../services/restore_report.dart';

/// Παράθυρο «Επαναφορά ολοκληρώθηκε»: μία γραμμή ανά στοιχείο με εικονίδιο
/// και χρώμα κατάστασης (πράσινο = επαναφέρθηκε, πορτοκαλί = δεν βρέθηκε στο
/// αντίγραφο, κόκκινο = αποτυχία), αντί για μήνυμα-«σούπα» σε μία σειρά.
Future<void> showRestoreReportDialog({
  required BuildContext context,
  required List<RestoreReportItem> items,
  String? fallbackText,
  String? preRestoreBackupPath,
  List<String> warnings = const <String>[],
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final preserved = preRestoreBackupPath?.trim() ?? '';
      final cleanWarnings = warnings
          .map((w) => w.trim())
          .where((w) => w.isNotEmpty)
          .toList(growable: false);

      return AlertDialog(
        title: const Text('Επαναφορά ολοκληρώθηκε'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Τι έγινε', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                if (items.isEmpty && (fallbackText?.trim().isNotEmpty ?? false))
                  Text(fallbackText!.trim())
                else
                  for (final item in items) _ReportRow(item: item),
                if (preserved.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Η προηγούμενη βάση φυλάχτηκε στο:\n$preserved',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (cleanWarnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Προειδοποιήσεις', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final warning in cleanWarnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• $warning',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Εντάξει'),
          ),
        ],
      );
    },
  );
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.item});

  final RestoreReportItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, Color color) = switch (item.status) {
      RestoreReportStatus.success => (
        Icons.check_circle_rounded,
        Colors.green.shade700,
      ),
      RestoreReportStatus.warning => (
        Icons.warning_amber_rounded,
        Colors.orange.shade800,
      ),
      RestoreReportStatus.failure => (
        Icons.error_rounded,
        theme.colorScheme.error,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${item.label}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: item.detail),
                ],
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
