import 'dart:async';
import 'dart:io';

import '../config/app_config.dart';
import '../services/settings_service.dart';

/// Η τύχη μιας δικτυακής διαδρομής που δεν απάντησε.
enum DatabasePathResolution {
  /// Υπάρχει διαδρομή για άνοιγμα (δικτυακή ή τοπική).
  resolved,

  /// Δικτυακή διαδρομή που δεν απαντά, και ο χρήστης δεν έχει αποφασίσει.
  networkUnreachable,
}

/// Αποτέλεσμα επίλυσης διαδρομής βάσης.
class ResolvedDatabasePath {
  const ResolvedDatabasePath._(
    this._path, {
    required this.outcome,
    required this.usedUncFallback,
    this.unreachablePath,
  });

  factory ResolvedDatabasePath({
    required String path,
    required bool usedUncFallback,
  }) => ResolvedDatabasePath._(
    path,
    outcome: DatabasePathResolution.resolved,
    usedUncFallback: usedUncFallback,
  );

  factory ResolvedDatabasePath.networkUnreachable(String configuredPath) =>
      ResolvedDatabasePath._(
        null,
        outcome: DatabasePathResolution.networkUnreachable,
        usedUncFallback: false,
        unreachablePath: configuredPath,
      );

  final String? _path;

  final DatabasePathResolution outcome;

  /// Η δικτυακή διαδρομή που δεν απάντησε — μόνο στο [networkUnreachable].
  final String? unreachablePath;

  /// True όταν ο χρήστης δέχτηκε την τοπική βάση επειδή το δίκτυο δεν απαντά.
  final bool usedUncFallback;

  /// Η διαδρομή προς άνοιγμα.
  ///
  /// Πετάει όταν δεν υπάρχει διαδρομή. Δεν είναι αυστηρότητα για την
  /// αυστηρότητα: η προηγούμενη μορφή επέστρεφε **πάντα** διαδρομή, οπότε ο
  /// καλών δεν είχε τρόπο να ξεχωρίσει «άνοιξε αυτό» από «το δίκτυο χάθηκε
  /// και σου έδωσα κάτι άλλο» — και η μετάπτωση περνούσε σιωπηλά.
  String get pathToOpen {
    final value = _path;
    if (value == null) {
      throw StateError(
        'Δεν υπάρχει διαδρομή προς άνοιγμα: η διαδρομή «$unreachablePath» '
        'δεν απάντησε και ο χρήστης δεν έχει αποφασίσει ακόμη.',
      );
    }
    return value;
  }
}

/// Η επιλογή «τοπική βάση, μόνο γι' αυτή τη φορά».
///
/// Ζει **όσο η διεργασία και τίποτα παραπάνω**: η ρυθμισμένη διαδρομή στις
/// Ρυθμίσεις δεν πειράζεται ποτέ, ώστε το επόμενο άνοιγμα να ξαναδοκιμάσει το
/// δίκτυο και ο χρήστης να μη χρειάζεται να θυμηθεί να το γυρίσει πίσω.
class LocalDatabaseSessionFallback {
  LocalDatabaseSessionFallback._();

  static String? _acceptedFor;
  static String? _localPath;

  /// Ο χρήστης δέχτηκε τη [localPath] στη θέση της [configuredPath].
  ///
  /// Η τοπική διαδρομή αποθηκεύεται **μαζί** με την απόφαση, και δεν
  /// ξαναϋπολογίζεται αργότερα: αλλιώς η βάση που άνοιγε δεν θα ήταν κατ'
  /// ανάγκη εκείνη που είδε ο χρήστης στο κουμπί.
  static void accept(String configuredPath, String localPath) {
    _acceptedFor = configuredPath.trim();
    _localPath = localPath.trim();
  }

  /// Ξεχνά την επιλογή — π.χ. όταν αλλάξει η ρυθμισμένη βάση.
  static void forget() {
    _acceptedFor = null;
    _localPath = null;
  }

  static bool isAcceptedFor(String configuredPath) {
    final accepted = _acceptedFor;
    return accepted != null && accepted == configuredPath.trim();
  }

  /// Η τοπική βάση που δέχτηκε ο χρήστης για τη [configuredPath].
  static String? acceptedLocalPathFor(String configuredPath) {
    if (!isAcceptedFor(configuredPath)) return null;
    final local = _localPath;
    return (local == null || local.isEmpty) ? null : local;
  }
}

/// Τι μπορεί να προσφερθεί ως τοπική βάση, και πόσο παλιά είναι.
class LocalDatabaseOffer {
  const LocalDatabaseOffer({required this.path, required this.lastModified});

  final String path;

  /// `null` όταν το αρχείο δεν υπάρχει — τότε δεν προσφέρεται τίποτα.
  final DateTime? lastModified;

  bool get exists => lastModified != null;
}

/// Η καλύτερη τοπική βάση που μπορεί να προσφερθεί **αυτή τη στιγμή**.
///
/// **«Τοπική» δεν είναι μια σταθερή διαδρομή** — είναι η πιο πρόσφατη τοπική
/// βάση που υπάρχει πραγματικά. Η προεπιλεγμένη διαδρομή είναι συχνά άδεια: σε
/// εγκατάσταση που δούλεψε πάντα με δικτυακή βάση δεν γράφτηκε ποτέ τίποτα
/// εκεί, και ένα κουμπί που δείχνει σε κενό δεν είναι διέξοδος.
///
/// **Σειρά αναζήτησης:** πρώτα οι πρόσφατες βάσεις (η πιο πρόσφατα
/// χρησιμοποιημένη πρώτη — είναι εκείνη που ο χρήστης αναγνωρίζει), και ως
/// τελευταία επιλογή η προεπιλεγμένη διαδρομή.
///
/// **Οι δικτυακές διαδρομές αποκλείονται** για δύο λόγους: δεν είναι τοπικές,
/// και ο έλεγχος ύπαρξης πάνω τους μπορεί να κρεμάσει ακριβώς την οθόνη που
/// υπάρχει για να δώσει διέξοδο.
///
/// Η ημερομηνία είναι το κρίσιμο: η τοπική βάση **δεν είναι κενή** — είναι ένα
/// παλιό, αληθινό αρχείο. Χωρίς να φαίνεται πόσο παλιό, ο χρήστης μπορεί να
/// καταγράφει κλήσεις σε περσινά δεδομένα νομίζοντας ότι δουλεύει κανονικά.
Future<LocalDatabaseOffer> localDatabaseOffer() async {
  for (final candidate in [
    ...await _recentLocalDatabasePaths(),
    AppConfig.defaultDbPath,
  ]) {
    final lastModified = await _lastModifiedOrNull(candidate);
    if (lastModified != null) {
      return LocalDatabaseOffer(path: candidate, lastModified: lastModified);
    }
  }
  return LocalDatabaseOffer(path: AppConfig.defaultDbPath, lastModified: null);
}

/// Οι πρόσφατες βάσεις που είναι **τοπικές**, με τη σειρά χρήσης τους.
Future<List<String>> _recentLocalDatabasePaths() async {
  try {
    final recent = await SettingsService().getRecentDatabasePaths();
    return recent
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .where((entry) => !AppConfig.isUncDatabasePath(entry))
        .toList();
  } catch (_) {
    return const <String>[];
  }
}

/// Πότε άλλαξε τελευταία, ή `null` αν δεν υπάρχει.
///
/// Χωρίς όριο χρόνου επίτηδες: εδώ φτάνουν μόνο τοπικές διαδρομές, και ένα
/// χρονόμετρο δεν θα προστάτευε από τίποτα ενώ επιβιώνει της οθόνης που το
/// άναψε.
Future<DateTime?> _lastModifiedOrNull(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.lastModified();
  } catch (_) {
    return null;
  }
}

/// Έλεγχος ύπαρξης αρχείου με σύντομο timeout (χρήσιμο για αργά δίκτυα).
Future<bool> databaseFileExistsQuick(String dbPath) async {
  try {
    return await File(
      dbPath,
    ).exists().timeout(const Duration(seconds: 2), onTimeout: () => false);
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
  if (await SettingsService().isDatabaseUnconfigured()) {
    return ResolvedDatabasePath(
      path: configuredPath.trim(),
      usedUncFallback: false,
    );
  }

  final p = configuredPath.trim().isEmpty
      ? AppConfig.defaultDbPath
      : configuredPath.trim();

  if (await databaseFileExistsQuick(p)) {
    return ResolvedDatabasePath(path: p, usedUncFallback: false);
  }

  // Διαδρομή με γράμμα δίσκου: το «δεν βρέθηκε το αρχείο» είναι ήδη σαφές
  // μήνυμα και το λέει ο καλών. Μόνο οι δικτυακές διαδρομές χρειάζονται
  // ξεχωριστή μεταχείριση, γιατί εκεί το αρχείο μπορεί κάλλιστα να υπάρχει
  // και να μη φτάνουμε σ' αυτό.
  if (!AppConfig.isUncDatabasePath(p)) {
    return ResolvedDatabasePath(path: p, usedUncFallback: false);
  }

  // Ανοίγει **ακριβώς** η βάση που είδε ο χρήστης στο κουμπί. Παλιότερα εδώ
  // ξαναϋπολογιζόταν η προεπιλεγμένη διαδρομή, οπότε η προσφορά και η ενέργεια
  // μπορούσαν να δείχνουν σε διαφορετικά αρχεία — και συνήθως έδειχναν.
  final accepted = LocalDatabaseSessionFallback.acceptedLocalPathFor(p);
  if (accepted == null) {
    return ResolvedDatabasePath.networkUnreachable(p);
  }
  return ResolvedDatabasePath(path: accepted, usedUncFallback: true);
}
