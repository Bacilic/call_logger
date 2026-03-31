import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/lock_diagnostic_service.dart';
import '../services/database_maintenance_service.dart';

/// Διάλογος αποτυχίας μετονομασίας βάσης: όνομα προορισμού αντιγράφου, άνοιγμα φακέλου,
/// και best-effort διαγνωστικό κλειδώματος (ίδια προσέγγιση με [DatabaseInitRunner] / `handle.exe`).
Future<void> showDatabaseRenameFailureDialog(
  BuildContext context,
  ReplaceDatabaseResult result,
) async {
  if (!context.mounted) return;
  final lockPath = result.sourceDbPathForLockDiagnostic?.trim();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Αποτυχία μετονομασίας'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.errorMessage ?? ''),
            const SizedBox(height: 12),
            Text(
              'Το νέο όνομα του παλιού αρχείου θα ήταν:',
              style: Theme.of(ctx).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              result.renameFailedFilePath != null
                  ? p.basename(result.renameFailedFilePath!)
                  : '—',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (lockPath != null && lockPath.isNotEmpty) ...[
              const SizedBox(height: 16),
              _LockDiagnosticSection(dbPath: lockPath),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Κλείσιμο'),
        ),
        if (result.renameFailedFolder != null)
          FilledButton(
            onPressed: () async {
              await DatabaseMaintenanceService.openFolderInExplorer(
                result.renameFailedFolder!,
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Άνοιγμα φακέλου'),
          ),
      ],
    ),
  );
}

class _LockDiagnosticSection extends StatefulWidget {
  const _LockDiagnosticSection({required this.dbPath});

  final String dbPath;

  @override
  State<_LockDiagnosticSection> createState() => _LockDiagnosticSectionState();
}

class _LockDiagnosticSectionState extends State<_LockDiagnosticSection> {
  late final Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = const LockDiagnosticService().detectLockingProcess(widget.dbPath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Διαγνωστικό κλειδώματος',
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
      subtitle: Text(
        'Όπως στην επανεκκίνηση ελέγχου βάσης (Sysinternals handle / PowerShell).',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: [
        FutureBuilder<String>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Σφάλμα: ${snap.error}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              );
            }
            return SelectableText(
              snap.data ?? '—',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Consolas', 'monospace'],
              ),
            );
          },
        ),
      ],
    );
  }
}
