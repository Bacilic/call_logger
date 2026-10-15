import 'update_manifest.dart';

/// Σχέση του αριθμού έκδοσης της διαθέσιμης ενημέρωσης με τον εγκατεστημένο.
///
/// Η απόφαση «υπάρχει νεότερη έκδοση;» παίρνεται πάντα από το build· η ετικέτα
/// `X.Y.Z` χρησιμεύει μόνο για να **εξηγηθεί στον χρήστη** μια εικόνα που
/// αλλιώς θα φαινόταν παράλογη.
enum UpdateVersionLabelRelation {
  /// Κανονική αναβάθμιση: η νέα έκδοση έχει μεγαλύτερο αριθμό. Καμία εξήγηση.
  higher,

  /// Ίδιος αριθμός έκδοσης, νεότερο κτίσιμο — αναδημιουργία της ίδιας έκδοσης
  /// (αλλαγές χωρίς καταχώρηση ιστορικού, ή επιδιόρθωση φακέλου ενημερώσεων).
  same,

  /// Μικρότερος αριθμός έκδοσης — αναπροσαρμογή της αρίθμησης εκδόσεων.
  lower,
}

/// Γιατί ο έλεγχος νέας έκδοσης δεν ολοκληρώθηκε.
///
/// Το [reason] συμπληρώνει την πρόταση «Δεν είναι δυνατός ο έλεγχος νέας
/// έκδοσης, επειδή …».
enum UpdateCheckFailure {
  /// Η ρύθμιση του φακέλου ζει στη βάση — με νεκρή σύνδεση δεν διαβάζεται.
  settingsUnreadable(
    'δεν διαβάστηκε η ρύθμιση του φακέλου ενημερώσεων από τη βάση δεδομένων',
  ),
  noFolderConfigured('δεν έχει οριστεί φάκελος ενημερώσεων'),
  folderUnreadable(
    'ο φάκελος ενημερώσεων δεν απαντά ή δεν περιέχει το version.json',
  ),
  manifestInvalid('το version.json του φακέλου ενημερώσεων δεν είναι έγκυρο'),
  timedOut('ο φάκελος ενημερώσεων δεν απάντησε εγκαίρως'),
  unexpected('παρουσιάστηκε απρόσμενο σφάλμα');

  const UpdateCheckFailure(this.reason);

  final String reason;
}

/// Αποτέλεσμα ελέγχου διαθέσιμης ενημέρωσης.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.updateAvailable,
    this.latestVersion,
    this.manifest,
    this.currentVersion,
    this.currentBuild,
    this.checkedAt,
  }) : failure = null;

  /// Έλεγχος που σκόπιμα δεν έγινε (build ανάπτυξης) — δεν είναι αποτυχία.
  const UpdateCheckResult.none()
    : updateAvailable = false,
      latestVersion = null,
      manifest = null,
      currentVersion = null,
      currentBuild = null,
      checkedAt = null,
      failure = null;

  /// Έλεγχος που επιχειρήθηκε και δεν ολοκληρώθηκε, με την αιτία του.
  const UpdateCheckResult.failed(UpdateCheckFailure this.failure)
    : updateAvailable = false,
      latestVersion = null,
      manifest = null,
      currentVersion = null,
      currentBuild = null,
      checkedAt = null;

  final bool updateAvailable;
  final String? latestVersion;
  final UpdateManifest? manifest;

  /// Πότε ολοκληρώθηκε ο έλεγχος που έδωσε αυτό το αποτέλεσμα. `null` όταν
  /// έλεγχος δεν έγινε πραγματικά (build ανάπτυξης, χωρίς φάκελο, αποτυχία) —
  /// τότε το UI δεν ισχυρίζεται «ελέγχθηκε» κάτι που δεν συνέβη.
  final DateTime? checkedAt;

  /// Η αιτία όταν ο έλεγχος επιχειρήθηκε και απέτυχε· `null` σε επιτυχία και
  /// σε έλεγχο που σκόπιμα δεν έγινε.
  final UpdateCheckFailure? failure;

  /// Ετικέτα έκδοσης της εγκατεστημένης εφαρμογής τη στιγμή του ελέγχου.
  final String? currentVersion;

  /// Build της εγκατεστημένης εφαρμογής τη στιγμή του ελέγχου.
  final int? currentBuild;

  /// Πώς συγκρίνεται ο αριθμός έκδοσης της ενημέρωσης με τον εγκατεστημένο.
  /// `null` όταν δεν υπάρχει διαθέσιμη ενημέρωση ή λείπουν στοιχεία.
  UpdateVersionLabelRelation? get versionLabelRelation {
    final available = manifest;
    final current = currentVersion;
    if (!updateAvailable || available == null || current == null) return null;
    final cmp = UpdateManifest.compareVersionLabels(available.version, current);
    if (cmp > 0) return UpdateVersionLabelRelation.higher;
    if (cmp == 0) return UpdateVersionLabelRelation.same;
    return UpdateVersionLabelRelation.lower;
  }

  /// Χρειάζεται επεξήγηση στο UI; Μόνο όταν ο αριθμός έκδοσης δεν ανεβαίνει —
  /// η σπάνια εικόνα που χωρίς εξήγηση μοιάζει με λάθος ή υποβάθμιση.
  bool get needsVersionLabelExplanation {
    final relation = versionLabelRelation;
    return relation == UpdateVersionLabelRelation.same ||
        relation == UpdateVersionLabelRelation.lower;
  }
}
