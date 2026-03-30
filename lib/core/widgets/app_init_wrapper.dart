import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_result.dart';
import '../database/database_init_progress_provider.dart';
import '../database/database_helper.dart';
import '../init/app_initializer.dart';
import '../../features/database/providers/backup_scheduler_provider.dart';
import '../../features/database/providers/database_backup_settings_provider.dart';
import 'app_shortcuts.dart';
import 'database_error_screen.dart';

/// Εκτελεί αρχικοποίηση εφαρμογής και προβάλλει live πρόοδο εκκίνησης.
class AppInitWrapper extends ConsumerStatefulWidget {
  const AppInitWrapper({super.key});

  @override
  ConsumerState<AppInitWrapper> createState() => _AppInitWrapperState();
}

class _AppInitWrapperState extends ConsumerState<AppInitWrapper> {
  AsyncValue<AppInitResult> _state = const AsyncLoading<AppInitResult>();

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_startInitialization);
  }

  Future<void> _startInitialization() async {
    final progressNotifier = ref.read(databaseInitProgressProvider.notifier);
    progressNotifier.reset();

    if (mounted) {
      setState(() {
        _state = const AsyncLoading<AppInitResult>();
      });
    }

    try {
      final initResult = await AppInitializer.initialize(
        progressNotifier: progressNotifier,
      );
      if (initResult.success) {
        await ref.read(databaseBackupSettingsProvider.notifier).load();
        await ref.read(backupSchedulerProvider.notifier).checkStartupAndStart();
      }
      if (!mounted) return;
      setState(() {
        _state = AsyncData<AppInitResult>(initResult);
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _state = AsyncError<AppInitResult>(e, st);
      });
    }
  }

  Future<void> _retryAppInitialization() async {
    try {
      await DatabaseHelper.instance.closeConnection();
    } catch (_) {}
    if (!mounted) return;
    await _startInitialization();
  }

  @override
  Widget build(BuildContext context) {
    return _state.when(
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
              Text(
                progress.currentStep,
                textAlign: TextAlign.center,
              ),
              if (progress.diagnosticInfo != null &&
                  progress.diagnosticInfo!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  progress.diagnosticInfo!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 4,
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
