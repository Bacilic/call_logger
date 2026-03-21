import '../database/database_init_result.dart';
import '../database/database_init_runner.dart';

/// Αποτέλεσμα αρχικοποίησης εφαρμογής (βάση δεδομένων + τρόπος λειτουργίας).
class AppInitResult {
  const AppInitResult({required this.result, required this.isLocalDevMode});

  final DatabaseInitResult result;
  final bool isLocalDevMode;

  bool get success => result.isSuccess;
  String? get message => result.message;
  String? get details => result.details;
  DatabaseStatus get dbStatus => result.status;
}

/// Αρχικοποίηση εφαρμογής: έλεγχος βάσης δεδομένων και υπολογισμός τρόπου λειτουργίας.
class AppInitializer {
  AppInitializer._();

  /// Εκτελεί τους ελέγχους βάσης (διαδρομή, ύπαρξη, δικαιώματα, σύνδεση, υγεία)
  /// και επιστρέφει [AppInitResult]. Δεν πετάει exception — τα σφάλματα επιστρέφονται στο result.
  static Future<AppInitResult> initialize() async {
    try {
      final runnerResult = await runDatabaseInitChecks(
        closeConnectionFirst: false,
      );
      return AppInitResult(
        result: runnerResult.result,
        isLocalDevMode: runnerResult.isLocalDevMode,
      );
    } catch (e, st) {
      return AppInitResult(
        result: DatabaseInitResult.fromException(e, null, st),
        isLocalDevMode: false,
      );
    }
  }
}
