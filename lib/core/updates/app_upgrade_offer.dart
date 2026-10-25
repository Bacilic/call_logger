import 'update_check_result.dart';
import 'update_manifest.dart';

/// Πόσο βέβαιη είναι η προσφορά αναβάθμισης ότι ξεμπλοκάρει τη βάση.
enum AppUpgradeConfidence {
  /// Το πακέτο δηλώνει ρητά ότι διαβάζει βάση αυτής της έκδοσης.
  resolvesForSure,

  /// Το πακέτο είναι νεότερο, αλλά δημοσιεύτηκε πριν καταγράφεται η έκδοση
  /// σχήματος — πιθανότατα αρκεί, χωρίς εγγύηση.
  likelyResolves,
}

/// Διαθέσιμη αναβάθμιση που έχει νόημα να προταθεί για συγκεκριμένη βάση.
class AppUpgradeOffer {
  const AppUpgradeOffer({required this.manifest, required this.confidence});

  final UpdateManifest manifest;
  final AppUpgradeConfidence confidence;

  /// Ετικέτα έκδοσης για το κουμπί (κενή όταν λείπει από το πακέτο).
  String get version => manifest.version;
}

/// Αξιολογεί αν το πακέτο του φακέλου ενημερώσεων λύνει το «βάση νεότερης
/// έκδοσης» — και άρα αν επιτρέπεται να προσφερθεί ως διέξοδος.
///
/// Επιστρέφει `null` σε τρεις περιπτώσεις, όλες με τον ίδιο λόγο: η
/// αναβάθμιση δεν θα άλλαζε τίποτα για τον χρήστη.
/// 1. Δεν υπάρχει πακέτο στον φάκελο ενημερώσεων.
/// 2. Το πακέτο δεν είναι νεότερο από την τρέχουσα εγκατάσταση.
/// 3. Το πακέτο δηλώνει έκδοση σχήματος που **δεν** φτάνει το αρχείο — εδώ η
///    γνώση είναι βέβαιη, οπότε η σιωπή είναι προτιμότερη από μια υπόσχεση
///    που θα κατέληγε στο ίδιο ακριβώς σφάλμα.
AppUpgradeOffer? evaluateAppUpgradeOffer({
  required UpdateManifest? manifest,
  required String currentVersion,
  required int currentBuild,
  required int fileSchemaVersion,
}) {
  if (manifest == null) return null;

  if (!_isNewerPackage(manifest, currentVersion, currentBuild)) return null;

  final packageSchema = manifest.schemaVersion;
  if (packageSchema != null && fileSchemaVersion > 0) {
    if (packageSchema < fileSchemaVersion) return null;
    return AppUpgradeOffer(
      manifest: manifest,
      confidence: AppUpgradeConfidence.resolvesForSure,
    );
  }

  return AppUpgradeOffer(
    manifest: manifest,
    confidence: AppUpgradeConfidence.likelyResolves,
  );
}

/// Το αποτέλεσμα της ερώτησης «υπάρχει αναβάθμιση που ξεμπλοκάρει τη βάση;»:
/// είτε η προσφορά, είτε η αιτία που δεν υπάρχει — ποτέ σιωπή.
class AppUpgradeProbe {
  const AppUpgradeProbe.offered(AppUpgradeOffer this.offer)
    : unavailableReason = null;

  const AppUpgradeProbe.unavailable(String this.unavailableReason)
    : offer = null;

  final AppUpgradeOffer? offer;

  /// Πρόταση για τον χρήστη: γιατί δεν προσφέρεται αναβάθμιση. `null` όταν
  /// υπάρχει προσφορά.
  final String? unavailableReason;
}

/// Μεταφράζει τον έλεγχο του φακέλου ενημερώσεων σε προσφορά ή αιτία.
///
/// Η αποτυχία λέγεται με το ίδιο κείμενο με το «Έλεγχος τώρα» του Ιστορικού
/// Αλλαγών, ώστε η ίδια αιτία να μην περιγράφεται με δύο τρόπους.
AppUpgradeProbe appUpgradeProbeFromCheck(
  UpdateCheckResult check, {
  required int fileSchemaVersion,
}) {
  final failure = check.failure;
  if (failure != null) {
    return AppUpgradeProbe.unavailable(failure.message);
  }
  final manifest = check.manifest;
  final current = check.currentVersion;
  final build = check.currentBuild;
  if (manifest == null || current == null || build == null) {
    return const AppUpgradeProbe.unavailable(
      'Αυτή είναι δοκιμαστική έκδοση της εφαρμογής· δεν ελέγχει τον φάκελο '
      'ενημερώσεων.',
    );
  }

  final offer = evaluateAppUpgradeOffer(
    manifest: manifest,
    currentVersion: current,
    currentBuild: build,
    fileSchemaVersion: fileSchemaVersion,
  );
  if (offer != null) return AppUpgradeProbe.offered(offer);

  final packageSchema = manifest.schemaVersion;
  if (_isNewerPackage(manifest, current, build) && packageSchema != null) {
    return AppUpgradeProbe.unavailable(
      'Η έκδοση ${manifest.version} του φακέλου ενημερώσεων διαβάζει βάσεις '
      'έως την έκδοση $packageSchema, ενώ αυτή η βάση είναι στην έκδοση '
      '$fileSchemaVersion — η αναβάθμιση δεν θα βοηθούσε.',
    );
  }
  return AppUpgradeProbe.unavailable(
    'Ο φάκελος ενημερώσεων έχει την έκδοση ${manifest.version}, που δεν '
    'είναι νεότερη από αυτή που τρέχει εδώ.',
  );
}

bool _isNewerPackage(UpdateManifest manifest, String current, int build) =>
    UpdateManifest.compareVersions(
      versionA: current,
      buildA: build,
      versionB: manifest.version,
      buildB: manifest.build,
    ) <
    0;
