import 'dart:async';

import '../config/app_config.dart';
import '../database/database_init_result.dart';
import '../database/database_init_runner.dart';
import '../services/dictionary_service.dart';
import '../services/spell_check_service.dart';

/// Αποτέλεσμα αρχικοποίησης εφαρμογής (βάση δεδομένων + τρόπος λειτουργίας).
class AppInitResult {
  const AppInitResult({
    required this.result,
    required this.isLocalDevMode,
    this.spellCheckReady = false,
  });

  final DatabaseInitResult result;
  final bool isLocalDevMode;

  /// True αν φορτώθηκε με επιτυχία το λεξικό ορθογραφίας (soft-fail, χωρίς crash).
  final bool spellCheckReady;

  bool get success => result.isSuccess;
  String? get message => result.message;
  String? get details => result.details;
  DatabaseStatus get dbStatus => result.status;
}

/// Αρχικοποίηση εφαρμογής: έλεγχος βάσης δεδομένων και υπολογισμός τρόπου λειτουργίας.
/// Χωρίς migrations ή flags παλιού σχήματος στο startup· μόνο έλεγχοι διαδρομής, σύνδεσης και υγείας (v1).
class AppInitializer {
  AppInitializer._();

  /// Εκτελεί τους ελέγχους βάσης (διαδρομή, ύπαρξη, δικαιώματα, σύνδεση, υγεία)
  /// και επιστρέφει [AppInitResult]. Δεν πετάει exception — τα σφάλματα επιστρέφονται στο result.
  static Future<AppInitResult> initialize() async {
    try {
      final runnerResult = await runDatabaseInitChecks(
        closeConnectionFirst: false,
      );
      var spellCheckReady = false;
      if (runnerResult.result.isSuccess) {
        try {
          final dict = DictionaryService(
            assetPath: AppConfig.greekDictionaryAsset,
          );
          await dict.load().timeout(const Duration(seconds: 8));
          final spell = LexiconSpellCheckService();
          await spell
              .init(lexiconMap: dict.stripKeyToDisplayMap)
              .timeout(const Duration(seconds: 8));
          spellCheckReady = true;
        } catch (_) {
          // Soft-fail: η εφαρμογή συνεχίζει χωρίς spell-check, ποτέ χωρίς τερματισμό εκκίνησης.
          spellCheckReady = false;
        }
      }
      return AppInitResult(
        result: runnerResult.result,
        isLocalDevMode: runnerResult.isLocalDevMode,
        spellCheckReady: spellCheckReady,
      );
    } catch (e, st) {
      return AppInitResult(
        result: DatabaseInitResult.fromException(e, null, st),
        isLocalDevMode: false,
        spellCheckReady: false,
      );
    }
  }
}
