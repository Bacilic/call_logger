import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../init/app_init_provider.dart';
import 'app_shortcuts.dart';

/// Φορτώνει το [appInitProvider] και εμφανίζει loading, σφάλμα ή την κύρια εφαρμογή.
class AppInitWrapper extends ConsumerWidget {
  const AppInitWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncResult = ref.watch(appInitProvider);

    return asyncResult.when(
      loading: () => const _InitLoadingScreen(),
      error: (err, _) => _InitErrorScreen(
        message: 'Προέκυψε σφάλμα κατά την εκκίνηση.',
        details: err.toString(),
      ),
      data: (initResult) {
        if (initResult.success) {
          return AppShortcuts(
            initialDatabaseResult: initResult.result,
            initialIsLocalDevMode: initResult.isLocalDevMode,
          );
        }
        return _InitErrorScreen(
          message: initResult.message ?? 'Η σύνδεση με τη βάση δεδομένων απέτυχε.',
          details: initResult.details,
        );
      },
    );
  }
}

class _InitLoadingScreen extends StatelessWidget {
  const _InitLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text('Φόρτωση εφαρμογής...'),
          ],
        ),
      ),
    );
  }
}

class _InitErrorScreen extends StatelessWidget {
  const _InitErrorScreen({required this.message, this.details});

  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                message,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              if (details != null && details!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  details!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
