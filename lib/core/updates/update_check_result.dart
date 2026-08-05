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

/// Αποτέλεσμα ελέγχου διαθέσιμης ενημέρωσης.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.updateAvailable,
    this.latestVersion,
    this.manifest,
    this.currentVersion,
    this.currentBuild,
  });

  const UpdateCheckResult.none()
    : updateAvailable = false,
      latestVersion = null,
      manifest = null,
      currentVersion = null,
      currentBuild = null;

  final bool updateAvailable;
  final String? latestVersion;
  final UpdateManifest? manifest;

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
    final cmp = UpdateManifest.compareVersionLabels(
      available.version,
      current,
    );
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
