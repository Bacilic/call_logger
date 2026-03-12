import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_result.dart';
import '../database/database_helper.dart';
import '../init/app_init_provider.dart';
import 'app_shortcuts.dart';
import 'database_error_screen.dart';

/// Φορτώνει το [appInitProvider] και εμφανίζει loading, σφάλμα ή την κύρια εφαρμογή.
class AppInitWrapper extends ConsumerWidget {
  const AppInitWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncResult = ref.watch(appInitProvider);

    return asyncResult.when(
      loading: () => const _InitLoadingScreen(),
      error: (err, _) {
        final result = DatabaseInitResult.fromException(err);
        return DatabaseErrorScreen(
          result: result,
          dbPath: result.path,
          onRetry: () async {
            await DatabaseHelper.instance.closeConnection();
            ref.invalidate(appInitProvider);
          },
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
          onRetry: () async {
            await DatabaseHelper.instance.closeConnection();
            ref.invalidate(appInitProvider);
          },
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
