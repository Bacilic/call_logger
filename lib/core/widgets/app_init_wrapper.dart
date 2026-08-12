import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_init_result.dart';
import '../database/database_init_progress_provider.dart';
import '../database/database_helper.dart';
import '../init/app_init_provider.dart';
import '../init/app_init_retry_runner.dart';
import '../init/startup_notices.dart';
import '../init/startup_window_placement.dart';
import '../providers/application_reset_provider.dart';
import '../services/application_reset_service.dart';
import '../services/crash_log_service.dart';
import '../../features/settings/widgets/pending_reset_database_screen.dart';
import 'app_shortcuts.dart';
import 'database_error_screen.dart';
import 'startup_splash_screen.dart';

/// Εκτελεί αρχικοποίηση εφαρμογής και προβάλλει live πρόοδο εκκίνησης.
class AppInitWrapper extends ConsumerStatefulWidget {
  const AppInitWrapper({super.key, this.showStartupSplash = true});

  /// Αν θα προβληθεί η οθόνη εκκίνησης πριν το κέλυφος.
  ///
  /// Η οθόνη έχει δικό της ελάχιστο χρόνο ζωής και έναν ρυθμιστή που χτυπά
  /// συνεχώς. Τα widget tests που στήνουν ολόκληρη την εφαρμογή για να
  /// ελέγξουν κάτι εντελώς άλλο δεν έχουν λόγο να την περιμένουν — και ο
  /// ρυθμιστής της θα κρέμαγε κάθε `pumpAndSettle`.
  final bool showStartupSplash;

  @override
  ConsumerState<AppInitWrapper> createState() => _AppInitWrapperState();
}

class _AppInitWrapperState extends ConsumerState<AppInitWrapper> {
  /// True μόλις η οθόνη εκκίνησης πει όσα είχε να πει.
  ///
  /// Ξεχωριστό από την κατάσταση του [appInitProvider] επίτηδες: η
  /// αρχικοποίηση μπορεί να τελειώσει σε μισό δευτερόλεπτο, αλλά η οθόνη έχει
  /// δικό της ελάχιστο χρόνο ζωής.
  bool _splashDone = false;

  /// Η οθόνη εκκίνησης παραδίδει τη σκυτάλη στην εφαρμογή.
  ///
  /// Το κέλυφος εμφανίζεται αμέσως και το παράθυρο μεγαλώνει μετά: αν
  /// περιμέναμε το λειτουργικό να αλλάξει διαστάσεις πριν χτίσουμε τη διεπαφή,
  /// θα υπήρχε ένα καρέ με άδειο, μεγάλο παράθυρο. Η αποτυχία της αλλαγής
  /// μεγέθους δεν αφορά τον χρήστη — η εφαρμογή είναι ήδη μπροστά του.
  void _leaveSplash() {
    if (!mounted) return;
    setState(() => _splashDone = true);
    unawaited(
      StartupWindowPlacement.restoreApplicationWindow().catchError((
        Object e,
        StackTrace st,
      ) {
        recordStartupNotice('Επαναφορά μεγέθους παραθύρου', e, st);
      }),
    );
  }

  Future<void> _retryAppInitialization() async {
    // Η επαναδοκιμή τρέχει ολόκληρη ακόμη κι αν το widget φύγει στο μεταξύ:
    // διακοπή στη μέση θα άφηνε τη βάση κλειστή. Το `mounted` φυλάει μόνο την
    // προβολή του μηνύματος.
    final outcome = await runAppInitRetry(ref: ref);
    if (outcome.succeeded || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.errorMessage!),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Widget _buildInitFailureScreen({
    required DatabaseInitResult result,
    required String? dbPath,
  }) {
    return FutureBuilder<bool>(
      future: ApplicationResetService.instance.hasPendingReset(),
      builder: (context, snapshot) {
        final pending = snapshot.data == true;
        if (pending && result.status == DatabaseStatus.fileNotFound) {
          return _buildPendingResetScreen();
        }
        return DatabaseErrorScreen(
          result: result,
          dbPath: dbPath,
          onRetry: _retryAppInitialization,
        );
      },
    );
  }

  Widget _buildPendingResetScreen() {
    return PendingResetDatabaseScreen(
      onLifecycleChanged: _retryAppInitialization,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingReset = ref.watch(applicationResetPendingProvider);
    if (pendingReset.value == true) {
      return _buildPendingResetScreen();
    }

    final asyncInit = ref.watch(appInitProvider);

    // Η οθόνη εκκίνησης μένει μπροστά όσο τρέχει η αρχικοποίηση ΚΑΙ όσο έχει
    // ακόμη βήματα να δείξει. Η αποτυχία την παρακάμπτει αμέσως: μπροστά σε
    // σφάλμα, ο χρήστης θέλει τα διαγνωστικά, όχι την εικόνα της ημέρας.
    final failed = asyncInit.hasError || asyncInit.value?.success == false;
    if (widget.showStartupSplash && !_splashDone && !failed) {
      return StartupSplashScreen(
        // Η έκδοση διαβάστηκε ήδη στην εκκίνηση για το ημερολόγιο σφαλμάτων —
        // δεν υπάρχει λόγος να ξαναρωτηθεί το λειτουργικό.
        appVersion: CrashLogService.instanceOrNull?.appVersion ?? '',
        initializationComplete: asyncInit.value?.success == true,
        onFinished: _leaveSplash,
      );
    }

    return asyncInit.when(
      loading: () => const _InitLoadingScreen(),
      error: (err, st) {
        final result = DatabaseInitResult.fromException(err, null, st);
        return _buildInitFailureScreen(result: result, dbPath: result.path);
      },
      data: (initResult) {
        if (initResult.success) {
          return AppShortcuts(
            initialDatabaseResult: initResult.result,
            initialIsLocalDevMode: initResult.isLocalDevMode,
            initialDatabaseProfile: initResult.databaseProfile,
            missingApplicationFiles: initResult.missingApplicationFiles,
          );
        }
        return _buildInitFailureScreen(
          result: initResult.result,
          dbPath: initResult.result.path,
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
