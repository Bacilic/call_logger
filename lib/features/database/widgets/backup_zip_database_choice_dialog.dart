import 'package:flutter/material.dart';

import '../services/backup_zip_inventory.dart';

/// Μόνο διεπαφή: δέχεται έτοιμη απογραφή και επιστρέφει την επιλογή χρήστη.
///
/// Δεν αποσυμπιέζει και δεν διαβάζει βάση.
Future<BackupZipEligibleCandidate?> showBackupZipDatabaseChoiceDialog({
  required BuildContext context,
  required BackupZipInventory inventory,
}) {
  assert(inventory.eligibleCandidates.length >= 2);
  return showDialog<BackupZipEligibleCandidate>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _BackupZipDatabaseChoiceDialog(inventory: inventory),
  );
}

class _BackupZipDatabaseChoiceDialog extends StatefulWidget {
  const _BackupZipDatabaseChoiceDialog({required this.inventory});

  final BackupZipInventory inventory;

  @override
  State<_BackupZipDatabaseChoiceDialog> createState() =>
      _BackupZipDatabaseChoiceDialogState();
}

class _BackupZipDatabaseChoiceDialogState
    extends State<_BackupZipDatabaseChoiceDialog> {
  BackupZipEligibleCandidate? _selected;
  bool _showRejected = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.inventory.eligibleCandidates.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inventory = widget.inventory;
    final rejected = inventory.rejectedCandidates;

    return AlertDialog(
      title: const Text('Επιλογή βάσης από το αντίγραφο'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(inventory.summarySentence),
              if (inventory.candidateLimitExceeded) ...[
                const SizedBox(height: 8),
                Text(
                  'Δεν ελέγχθηκαν όλα τα αρχεία βάσης: παραλείφθηκαν '
                  '${inventory.uncheckedCandidateCount} λόγω ανώτατου ορίου.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Έγκυρες βάσεις', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              RadioGroup<BackupZipEligibleCandidate>(
                groupValue: _selected,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selected = v);
                },
                child: Column(
                  children: [
                    for (final c in inventory.eligibleCandidates)
                      RadioListTile<BackupZipEligibleCandidate>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: c,
                        title: Text(c.displayName),
                        subtitle: Text(_candidateSubtitle(c)),
                      ),
                  ],
                ),
              ),
              if (rejected.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => _showRejected = !_showRejected),
                  child: Row(
                    children: [
                      Icon(
                        _showRejected ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Απορριφθέντα (${rejected.length})',
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
                if (_showRejected) ...[
                  const SizedBox(height: 8),
                  for (final r in rejected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${r.displayName} — ${r.reason}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Συνέχεια'),
        ),
      ],
    );
  }

  String _candidateSubtitle(BackupZipEligibleCandidate c) {
    final parts = <String>[_formatBytes(c.sizeBytes)];
    if (c.checkFailed) {
      parts.add(c.checkWarning ?? 'Ο έλεγχος απέτυχε');
    } else {
      final calls = c.profile.callCount;
      if (calls != null) {
        parts.add('κλήσεις: $calls');
      }
      final latest = c.profile.latestCallDate?.trim() ?? '';
      if (latest.isNotEmpty) {
        parts.add('τελευταία κλήση: $latest');
      }
    }
    return parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
