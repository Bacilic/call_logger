import 'package:flutter/material.dart';

import '../database/database_init_result.dart';
import '../../features/settings/screens/settings_screen.dart';

/// Οθόνη σφάλματος βάσης δεδομένων (fail-fast).
/// Εμφανίζει μήνυμα και διαδρομή ανάλογα με το [result] και κουμπιά Ρυθμίσεις / Επαναδοκιμή.
class DatabaseErrorScreen extends StatelessWidget {
  const DatabaseErrorScreen({
    super.key,
    required this.result,
    required this.dbPath,
    required this.onRetry,
  });

  final DatabaseInitResult result;
  final String? dbPath;
  final Future<void> Function() onRetry;

  String get _displayMessage {
    switch (result.status) {
      case DatabaseStatus.fileNotFound:
        return 'Δεν βρέθηκε βάση δεδομένων.';
      case DatabaseStatus.accessDenied:
        return 'Αδυναμία εγγραφής ή πρόσβασης στο αρχείο βάσης.';
      case DatabaseStatus.corruptedOrInvalid:
        return 'Μη έγκυρο αρχείο βάσης.';
      case DatabaseStatus.success:
        return result.message ?? 'Η σύνδεση πέτυχε.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = result.path ?? dbPath;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 24),
              Text(
                _displayMessage,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              if (result.message != null &&
                  result.message != _displayMessage) ...[
                const SizedBox(height: 8),
                Text(
                  result.message!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (path != null && path.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    path,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 3,
                  ),
                ),
              ],
              if (result.details != null && result.details!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  result.details!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings),
                label: const Text('Ρυθμίσεις'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async => await onRetry(),
                icon: const Icon(Icons.refresh),
                label: const Text('Επαναδοκιμή'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
