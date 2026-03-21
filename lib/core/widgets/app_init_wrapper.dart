import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_result.dart';
import '../database/database_helper.dart';
import '../init/app_init_provider.dart';
import 'app_shortcuts.dart';
import 'database_error_screen.dart';

/// Κλείνει τη σύνδεση βάσης, επαναλαμβάνει το [appInitProvider] με σειρά και ασφαλή [BuildContext.mounted].
Future<void> _retryAppInitialization(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    await DatabaseHelper.instance.closeConnection();
  } catch (_) {}
  if (!context.mounted) return;
  ref.invalidate(appInitProvider);
  try {
    await ref.read(appInitProvider.future);
  } catch (_) {}
}

/// Φορτώνει το [appInitProvider] και εμφανίζει loading, σφάλμα ή την κύρια εφαρμογή.
class AppInitWrapper extends ConsumerWidget {
  const AppInitWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncResult = ref.watch(appInitProvider);

    return asyncResult.when(
      loading: () => const _InitLoadingScreen(),
      error: (err, st) {
        final result = DatabaseInitResult.fromException(err, null, st);
        return DatabaseErrorScreen(
          result: result,
          dbPath: result.path,
          onRetry: () => _retryAppInitialization(context, ref),
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
          onRetry: () => _retryAppInitialization(context, ref),
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
