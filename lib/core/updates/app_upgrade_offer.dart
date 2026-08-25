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

  final isNewer =
      UpdateManifest.compareVersions(
        versionA: currentVersion,
        buildA: currentBuild,
        versionB: manifest.version,
        buildB: manifest.build,
      ) <
      0;
  if (!isNewer) return null;

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
