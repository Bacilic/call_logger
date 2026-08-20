import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/database/providers/backup_scheduler_provider.dart';
import '../../features/database/providers/database_backup_settings_provider.dart';
import '../database/database_file_classifier.dart';
import '../database/database_init_progress_provider.dart';
import '../database/database_init_result.dart';
import '../database/database_init_runner.dart';
import '../database/database_helper.dart';
import '../database/database_path_resolution.dart';
import '../database/lock_diagnostic_service.dart';
import '../services/asset_residue_cleaner.dart';
import '../services/core_lexicon_service.dart';
import '../services/current_operator.dart';
import '../services/operator_identity.dart';
import '../services/settings_service.dart';
import '../updates/update_residue_cleaner.dart';
import 'startup_engine_failure.dart';
import 'startup_notices.dart';
import 'startup_structural_check.dart';

DatabaseInitResult _appendStartupNoticesToFailureDetails(
  DatabaseInitResult base,
) {
  if (base.isSuccess) return base;
  final report = startupNoticesReport();
  if (report == null) return base;
  final existing = base.details?.trim();
  final merged = (existing == null || existing.isEmpty)
      ? report
      : '$existing\n\n$report';
  return base.copyWith(details: merged);
}

/// Καθαρίζει τα υπολείμματα προηγούμενης ενημέρωσης, ανακοινώνοντας βήμα **μόνο**
/// όταν υπάρχει κάτι να καθαριστεί.
///
/// Η σιωπή είναι ο κανόνας: στη συντριπτική πλειονότητα των ανοιγμάτων δεν
/// υπάρχει τίποτα να φύγει, και η εκκίνηση δεν έχει λόγο να αναφέρει έναν έλεγχο
/// που δεν έκανε τίποτα. Ο καθαρισμός είναι νοικοκυριό, όχι προϋπόθεση: καμία
/// αποτυχία του δεν εμποδίζει την εφαρμογή να ανοίξει.
Future<void> cleanUpdateResidue({
  DatabaseInitProgressNotifier? progressNotifier,
  UpdateResidueCleaner? cleaner,
}) async {
  try {
    final worker = cleaner ?? UpdateResidueCleaner.production();
    final scan = await worker.scan();
    if (!scan.hasWork) return;
    progressNotifier?.setStep('Καθαρισμός υπολειμμάτων ενημέρωσης');
    await worker.clean(scan);
  } catch (_) {}
}

/// Σβήνει από τον φάκελο πόρων της εγκατάστασης ό,τι δεν ανήκει πουθενά.
///
/// Επιστρέφει `true` μόνο όταν έφυγε κάτι — τότε και μόνο τότε το βήμα
/// εμφανίζεται στην οθόνη εκκίνησης. Στα περισσότερα ανοίγματα δεν υπάρχει
/// τίποτα να καθαριστεί και η σιωπή είναι η σωστή απάντηση.
Future<bool> cleanAssetResidue({AssetResidueCleaner? cleaner}) async {
  final worker = cleaner ?? AssetResidueCleaner.production();
  final scan = await worker.scan();
  if (!scan.hasWork) return false;
  final removed = await worker.clean(scan);
  return removed.isNotEmpty;
}

/// Αποτέλεσμα αρχικοποίησης εφαρμογής (βάση δεδομένων + τρόπος λειτουργίας).
class AppInitResult {
  const AppInitResult({
    required this.result,
    required this.isLocalDevMode,
    this.spellCheckReady = false,
    this.databaseProfile,
    this.missingApplicationFiles = const <String>[],
  });

  final DatabaseInitResult result;
  final bool isLocalDevMode;

  /// Ελλείποντα κρίσιμα αρχεία εφαρμογής από τον δομικό έλεγχο της εκκίνησης.
  final List<String> missingApplicationFiles;

  /// True αν φορτώθηκε λεξικό-πυρήνας από αποθηκευμένη διαδρομή.
  final bool spellCheckReady;

  /// Προφίλ αρχείου βάσης από την ταξινόμηση εκκίνησης (χωρίς νέο query).
  final DatabaseFileProfile? databaseProfile;

  bool get success => result.isSuccess;
  String? get message => result.message;
  String? get details => result.details;
  DatabaseStatus get dbStatus => result.status;
}

/// Αρχικοποίηση εφαρμογής: έλεγχος βάσης δεδομένων και υπολογισμός τρόπου λειτουργίας.
class AppInitializer {
  AppInitializer._();

  static Future<void> activateBackupSchedulingAfterDatabaseReady(
    Ref ref,
  ) async {
    // Soft-fail: μετά από επιτυχή βάση, ΚΑΝΕΝΑ προαιρετικό βήμα δεν επιτρέπεται
    // να ρίξει την εκκίνηση. Τα αντίγραφα ασφαλείας είναι νοικοκυριό — ένας
    // άφταστος φάκελος προορισμού (π.χ. UNC του νοσοκομείου, ανοιγμένος από το
    // σπίτι) δεν δικαιούται να ντύσει μια υγιή βάση με οθόνη σφάλματος.
    await runStartupHousekeeping('Έλεγχος αντιγράφων ασφαλείας', () async {
      await ref.read(databaseBackupSettingsProvider.notifier).load();
      await ref.read(backupSchedulerProvider.notifier).checkStartupAndStart();
      return true;
    });
  }

  /// Αναγνωρίζει ποιος χρησιμοποιεί την εφαρμογή, μόλις η βάση είναι έτοιμη.
  ///
  /// Τρέχει και σε κάθε αλλαγή βάσης, γιατί τα προφίλ ζουν **μέσα** στη βάση:
  /// η επόμενη μπορεί να μην ξέρει καθόλου αυτό το πρόσωπο.
  ///
  /// Αποτυχία δεν εμποδίζει την εκκίνηση — η ταυτότητα είναι ευκολία, όχι
  /// προϋπόθεση. Το αποτέλεσμα είναι ορατό εκεί που έχει σημασία: το Ιστορικό
  /// γράφει παύλα αντί για όνομα, όπως έκανε πάντα πριν υπάρξουν προφίλ.
  static Future<void> _resolveCurrentOperator() async {
    try {
      final db = await DatabaseHelper.instance.database;
      await OperatorIdentity.resolveAndActivate(db);
    } catch (_) {
      CurrentOperator.reset();
    }
  }

  static Future<AppInitResult> initialize({
    DatabaseInitProgressNotifier? progressNotifier,
  }) async {
    try {
      // Στην εκκίνηση δεν υπάρχει τίποτα αποθηκευμένο και οι έλεγχοι τρέχουν
      // κανονικά. Μετά από εναλλαγή βάσης όμως η βάση μόλις επαληθεύτηκε —
      // τρίτο άνοιγμα στη σειρά δεν προσθέτει καμία βεβαιότητα.
      final runnerResult = await runDatabaseInitChecks(
        closeConnectionFirst: false,
        reuseIfFresh: true,
        progressNotifier: progressNotifier,
      );
      var spellCheckReady = false;
      if (runnerResult.result.isSuccess) {
        await _resolveCurrentOperator();
        try {
          spellCheckReady = await CoreLexiconService.instance
              .bootstrapFromSavedPath();
        } catch (_) {
          spellCheckReady = false;
        }
        await cleanUpdateResidue(progressNotifier: progressNotifier);
      }
      progressNotifier?.setStep(
        'Ολοκλήρωση εκκίνησης',
        clearSecondsRemaining: true,
        kind: StartupStepKind.completed,
      );
      return AppInitResult(
        result: _appendStartupNoticesToFailureDetails(runnerResult.result),
        isLocalDevMode: runnerResult.isLocalDevMode,
        spellCheckReady: spellCheckReady,
        databaseProfile: runnerResult.databaseProfile,
        missingApplicationFiles: runnerResult.missingApplicationFiles,
      );
    } catch (e, st) {
      // Ο runner δεν πρόλαβε να επιστρέψει· ο δομικός έλεγχος οφείλει να
      // προηγηθεί και εδώ, αλλιώς η μοναδική διαδρομή που τον παρακάμπτει
      // είναι ακριβώς αυτή που δείχνει το πιο ακατανόητο σφάλμα.
      final missingApplicationFiles = detectMissingApplicationFiles();
      var result = resolveStartupFailureResult(
        fallbackError: e,
        fallbackStack: st,
      );
      if (e is TimeoutException || e is DatabaseInitException) {
        try {
          progressNotifier?.setStep('Εντοπισμός διεργασίας');
          final configured = await SettingsService().getDatabasePath();
          final resolved = await resolveEffectiveDatabasePath(configured);
          final diagnostic = await const LockDiagnosticService()
              .detectLockingProcess(resolved.path);
          if (diagnostic.trim().isNotEmpty) {
            final details = result.details?.trim();
            final merged = (details == null || details.isEmpty)
                ? diagnostic
                : '$details\n\n--- Lock diagnostics ---\n$diagnostic';
            result = result.copyWith(details: merged);
            progressNotifier?.setDiagnostic(diagnostic);
          }
        } catch (_) {}
      }
      return AppInitResult(
        result: _appendStartupNoticesToFailureDetails(
          withMissingApplicationFilesFirst(result, missingApplicationFiles),
        ),
        isLocalDevMode: false,
        spellCheckReady: false,
        databaseProfile: null,
        missingApplicationFiles: missingApplicationFiles,
      );
    }
  }
}
