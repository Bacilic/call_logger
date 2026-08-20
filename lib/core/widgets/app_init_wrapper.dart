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
import '../models/operator.dart';
import '../providers/application_reset_provider.dart';
import '../services/application_reset_service.dart';
import '../services/crash_log_service.dart';
import '../services/current_operator.dart';
import '../services/operator_identity.dart';
import '../../features/operators/screens/operator_picker_screen.dart';
import '../../features/settings/widgets/pending_reset_database_screen.dart';
import 'app_shortcuts.dart';
import 'database_error_screen.dart';
import 'startup_splash_screen.dart';

/// Εκτελεί αρχικοποίηση εφαρμογής και προβάλλει live πρόοδο εκκίνησης.
class AppInitWrapper extends ConsumerStatefulWidget {
  const AppInitWrapper({
    super.key,
    this.showStartupScreens = true,
    @visibleForTesting this.windowRestorer,
  });

  /// Επαναφορά μεγέθους/θέσης παραθύρου (εγχύσιμη — στα τεστ δεν υπάρχει
  /// πραγματικό παράθυρο, και η σειρά είναι ακριβώς αυτό που ελέγχεται).
  final Future<void> Function()? windowRestorer;

  /// Αν θα προβληθούν **όλες** οι οθόνες που προηγούνται του κελύφους: η κάρτα
  /// εκκίνησης και η επιλογή χρήστη.
  ///
  /// Τα widget tests που στήνουν ολόκληρη την εφαρμογή για να ελέγξουν κάτι
  /// εντελώς άλλο δεν έχουν λόγο να τις περιμένουν: η κάρτα εκκίνησης έχει
  /// ρυθμιστή που χτυπά συνεχώς και θα κρέμαγε κάθε `pumpAndSettle`, ενώ η
  /// επιλογή χρήστη θα στεκόταν μπροστά σε κάθε δοκιμαστική βάση που δεν έχει
  /// προφίλ.
  ///
  /// Είναι **ρητή σημαία και όχι ανίχνευση περιβάλλοντος**: κρυφή συμπεριφορά
  /// που εξαρτάται από το πού τρέχει η εφαρμογή δεν βρίσκεται όταν χαλάσει.
  /// Κάθε νέα οθόνη πριν το κέλυφος περνά από εδώ.
  final bool showStartupScreens;

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

  /// True μόλις ο χρήστης δηλώσει ποιος είναι — ή όταν δεν χρειάστηκε να ρωτηθεί.
  bool _operatorChosen = false;

  /// Τα προφίλ προς επιλογή, φορτωμένα **μία φορά**: χωρίς αυτό, κάθε
  /// ξαναχτίσιμο θα ξεκινούσε νέα ανάγνωση και η λίστα θα αναβόσβηνε.
  Future<List<Operator>>? _selectableProfiles;

  /// Η οθόνη εκκίνησης παραδίδει τη σκυτάλη στην εφαρμογή.
  ///
  /// Το παράθυρο επανέρχεται **πρώτα** και το κέλυφος χτίζεται μετά. Η κάρτα
  /// εκκίνησης ανοίγει σε μέγεθος μικρότερο από το ελάχιστο για το οποίο είναι
  /// σχεδιασμένη η διεπαφή· αν το κέλυφος χτιζόταν όσο το παράθυρο είναι ακόμη
  /// στο μέγεθος της κάρτας, η διεπαφή θα ζωγραφιζόταν σε ύψος που δεν της
  /// φτάνει και θα ξεχείλιζε. Δεν είναι θεωρητικό: σε αργό μηχάνημα η επαναφορά
  /// κρατά αρκετά καρέ ώστε να προλάβει να φανεί, ενώ σε γρήγορο δεν προλαβαίνει
  /// ποτέ — γι' αυτό και εμφανιζόταν μόνο στον έναν υπολογιστή.
  ///
  /// Η κάρτα δεν «αδειάζει» στο μεταξύ: είναι στοίβα σε πλήρη έκταση και
  /// ακολουθεί όποιο μέγεθος κι αν πάρει το παράθυρο.
  ///
  /// Η αποτυχία ή η αργοπορία της επαναφοράς δεν κρατά την πόρτα κλειστή: το
  /// χρονικό όριο εγγυάται ότι η εφαρμογή ανοίγει ούτως ή άλλως.
  Future<void> _leaveSplash() async {
    if (!mounted) return;
    final restore =
        widget.windowRestorer ?? StartupWindowPlacement.restoreApplicationWindow;
    try {
      await restore().timeout(kWindowRestoreTimeout);
    } catch (e, st) {
      recordStartupNotice('Επαναφορά μεγέθους παραθύρου', e, st);
    }
    if (!mounted) return;
    setState(() => _splashDone = true);
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

  /// Η οθόνη «Ποιος είστε;» — μόνο όταν ο λογαριασμός Windows δεν αρκεί.
  ///
  /// Επιστρέφει `null` όταν δεν χρειάζεται, ώστε η συνηθισμένη εκκίνηση (ο
  /// καθένας στον δικό του λογαριασμό) να μη βλέπει ποτέ τίποτα.
  Widget? _buildOperatorPickerIfNeeded() {
    if (CurrentOperator.active != null) return null;

    return FutureBuilder<List<Operator>>(
      future: _selectableProfiles ??= _loadSelectableProfiles(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _InitLoadingScreen();
        }
        return OperatorPickerScreen(
          profiles: snapshot.data ?? const <Operator>[],
          suggestedName: OperatorIdentity.suggestedDisplayName(),
          hasWindowsAccount:
              OperatorIdentity.suggestedDisplayName().isNotEmpty,
          onPick: (operator) {
            OperatorIdentity.activateForSession(operator);
            setState(() => _operatorChosen = true);
          },
          onCreate: (displayName, bindCurrentAccount) async {
            final db = await DatabaseHelper.instance.database;
            await OperatorIdentity.createAndActivate(
              db,
              displayName: displayName,
              bindCurrentAccount: bindCurrentAccount,
            );
            if (!mounted) return;
            setState(() => _operatorChosen = true);
          },
        );
      },
    );
  }

  Future<List<Operator>> _loadSelectableProfiles() async {
    final db = await DatabaseHelper.instance.database;
    return OperatorIdentity.selectableProfiles(db);
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
    if (widget.showStartupScreens && !_splashDone && !failed) {
      return StartupSplashScreen(
        // Η έκδοση διαβάστηκε ήδη στην εκκίνηση για το ημερολόγιο σφαλμάτων —
        // δεν υπάρχει λόγος να ξαναρωτηθεί το λειτουργικό.
        appVersion: CrashLogService.instanceOrNull?.appVersion ?? '',
        initializationComplete: asyncInit.value?.success == true,
        onFinished: () => unawaited(_leaveSplash()),
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
          if (widget.showStartupScreens && !_operatorChosen) {
            final picker = _buildOperatorPickerIfNeeded();
            if (picker != null) return picker;
          }
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
