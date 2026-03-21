import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_init_result.dart';
import '../../features/settings/screens/settings_screen.dart';

/// Οθόνη σφάλματος βάσης / γενικού σφάλματος.
/// Λεπτομερή ελληνικά μηνύματα, επιλέξιμο κείμενο, αντιγραφή πλήρους αναφοράς.
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

  String get _fallbackShortTitle {
    switch (result.status) {
      case DatabaseStatus.fileNotFound:
        return 'Δεν βρέθηκε βάση δεδομένων.';
      case DatabaseStatus.accessDenied:
        return 'Πρόβλημα πρόσβασης στο αρχείο βάσης.';
      case DatabaseStatus.corruptedOrInvalid:
        return 'Μη έγκυρο ή κατεστραμμένο αρχείο βάσης.';
      case DatabaseStatus.applicationError:
        return 'Σφάλμα εφαρμογής ή υποσυστήματος.';
      case DatabaseStatus.success:
        return result.message ?? 'Η σύνδεση πέτυχε.';
    }
  }

  String get _primaryMessage {
    final m = result.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return _fallbackShortTitle;
  }

  Future<void> _copyFullReport(BuildContext context) async {
    final text = result.buildClipboardReport(dbPathFallback: dbPath);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Αντιγράφηκε πλήρης αναφορά σφάλματος στο πρόχειρο.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = result.path ?? dbPath;
    final details = result.details?.trim();
    final original = result.originalExceptionText?.trim();
    final stack = result.stackTraceText?.trim();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.error_outline,
                size: 56,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Σφάλμα',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          _primaryMessage,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        if (details != null && details.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SelectableText(
                            details,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (path != null && path.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Διαδρομή',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            path,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (result.technicalCode != null &&
                            result.technicalCode!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SelectableText(
                            result.technicalCode!.trim(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (original != null &&
                            original.isNotEmpty &&
                            original != _primaryMessage) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Αρχικό μήνυμα σφάλματος (runtime)',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            original,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (stack != null && stack.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Stack trace',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            stack,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _copyFullReport(context),
                icon: const Icon(Icons.copy),
                label: const Text('Αντιγραφή πλήρους σφάλματος'),
              ),
              const SizedBox(height: 12),
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
                onPressed: () async => onRetry(),
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
