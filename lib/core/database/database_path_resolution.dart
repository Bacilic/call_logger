import 'dart:async';
import 'dart:io';

import '../config/app_config.dart';

/// Αποτέλεσμα επίλυσης διαδρομής βάσης (μετά από πιθανό fallback από UNC).
class ResolvedDatabasePath {
  const ResolvedDatabasePath({
    required this.path,
    required this.usedUncFallback,
  });

  final String path;

  /// True όταν η ρυθμισμένη διαδρομή ήταν UNC και αντικαταστάθηκε από την προεπιλογή.
  final bool usedUncFallback;
}

/// Έλεγχος ύπαρξης αρχείου με σύντομο timeout (χρήσιμο για αργά δίκτυα).
Future<bool> databaseFileExistsQuick(String dbPath) async {
  try {
    return await File(dbPath).exists().timeout(
          const Duration(seconds: 2),
          onTimeout: () => false,
        );
  } on TimeoutException {
    return false;
  } catch (_) {
    return false;
  }
}

/// Επιλύει την πραγματική διαδρομή ανοίγματος: κενό → προεπιλογή· αν το UNC δεν
/// υπάρχει/είναι απρόσιτο → προεπιλογή portable δίπλα στο εκτελέσιμο.
Future<ResolvedDatabasePath> resolveEffectiveDatabasePath(
  String configuredPath,
) async {
  var p = configuredPath.trim().isEmpty
      ? AppConfig.defaultDbPath
      : configuredPath.trim();
  var usedFallback = false;
  if (!await databaseFileExistsQuick(p) && AppConfig.isUncDatabasePath(p)) {
    p = AppConfig.defaultDbPath;
    usedFallback = true;
    final parent = File(p).parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
  }
  return ResolvedDatabasePath(path: p, usedUncFallback: usedFallback);
}
