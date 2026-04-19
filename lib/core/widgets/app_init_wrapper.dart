import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_result.dart';
import '../database/database_init_progress_provider.dart';
import '../database/database_helper.dart';
import '../init/app_init_provider.dart';
import 'app_shortcuts.dart';
import 'database_error_screen.dart';

/// Εκτελεί αρχικοποίηση εφαρμογής και προβάλλει live πρόοδο εκκίνησης.
class AppInitWrapper extends ConsumerStatefulWidget {
  const AppInitWrapper({super.key});

  @override
  ConsumerState<AppInitWrapper> createState() => _AppInitWrapperState();
}

class _AppInitWrapperState extends ConsumerState<AppInitWrapper> {
  Future<void> _retryAppInitialization() async {
    try {
      await DatabaseHelper.instance.closeConnection();
    } catch (_) {}
    if (!mounted) return;
    ref.invalidate(appInitProvider);
  }

  @override
  Widget build(BuildContext context) {
    final asyncInit = ref.watch(appInitProvider);
    return asyncInit.when(
      loading: () => const _InitLoadingScreen(),
      error: (err, st) {
        final result = DatabaseInitResult.fromException(err, null, st);
        return DatabaseErrorScreen(
          result: result,
          dbPath: result.path,
          onRetry: _retryAppInitialization,
        );
      },
      data: (initResult) {
        if (initResult.success) {
          return AppShortcuts(
            initialDatabaseResult: initResult.result,
            initialIsLocalDevMode: initResult.isLocalDevMode,
          );
        }
        return DatabaseErrorScreen(
          result: initResult.result,
          dbPath: initResult.result.path,
          onRetry: _retryAppInitialization,
        );
      },
    );
  }
}

class _InitLoadingScreen extends ConsumerWidget {
  const _InitLoadingScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(databaseInitProgressProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text('Φόρτωση εφαρμογής...'),
              const SizedBox(height: 10),
              if (progress.secondsRemaining != null)
                Text(
                  'Προσπάθεια άνοιγμα βάσης σε ${progress.secondsRemaining} δευτερόλεπτα',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (progress.secondsRemaining != null) const SizedBox(height: 10),
              Text(progress.currentStep, textAlign: TextAlign.center),
              if (progress.isOpeningAttemptActive) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: DatabaseHelper.instance.requestOpeningAbort,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Διακοπή τώρα'),
                ),
              ],
              if (progress.diagnosticInfo != null &&
                  progress.diagnosticInfo!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                SelectableText(
                  progress.diagnosticInfo!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: progress.diagnosticInfo!.trim()),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Τα διαγνωστικά αντιγράφηκαν στο πρόχειρο.',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Αντιγραφή διαγνωστικών'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
