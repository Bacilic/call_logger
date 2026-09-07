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

  /// Ο χρήστης δέχτηκε την τοπική βάση αντί για τη [configuredPath].
  static void accept(String configuredPath) {
    _acceptedFor = configuredPath.trim();
  }

  /// Ξεχνά την επιλογή — π.χ. όταν αλλάξει η ρυθμισμένη βάση.
  static void forget() {
    _acceptedFor = null;
  }

  static bool isAcceptedFor(String configuredPath) {
    final accepted = _acceptedFor;
    return accepted != null && accepted == configuredPath.trim();
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

/// Τι υπάρχει σήμερα στην προεπιλεγμένη τοπική διαδρομή.
///
/// Η ημερομηνία είναι το κρίσιμο: η τοπική βάση **δεν είναι κενή** — είναι ένα
/// παλιό, αληθινό αρχείο. Χωρίς να φαίνεται πόσο παλιό, ο χρήστης μπορεί να
/// καταγράφει κλήσεις σε περσινά δεδομένα νομίζοντας ότι δουλεύει κανονικά.
Future<LocalDatabaseOffer> localDatabaseOffer() async {
  // Χωρίς όριο χρόνου επίτηδες: η προεπιλεγμένη διαδρομή είναι πάντα τοπικός
  // δίσκος (δίπλα στο εκτελέσιμο ή στον φάκελο του προφίλ). Ένα χρονόμετρο εδώ
  // δεν θα προστάτευε από τίποτα και επιβιώνει της οθόνης που το άναψε.
  final path = AppConfig.defaultDbPath;
  try {
    final file = File(path);
    if (!await file.exists()) {
      return LocalDatabaseOffer(path: path, lastModified: null);
    }
    return LocalDatabaseOffer(
      path: path,
      lastModified: await file.lastModified(),
    );
  } catch (_) {
    return LocalDatabaseOffer(path: path, lastModified: null);
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

  if (!LocalDatabaseSessionFallback.isAcceptedFor(p)) {
    return ResolvedDatabasePath.networkUnreachable(p);
  }

  final local = AppConfig.defaultDbPath;
  final parent = File(local).parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
  return ResolvedDatabasePath(path: local, usedUncFallback: true);
}
