import 'backup_zip_inventory.dart';

/// Αποτέλεσμα της καθαρής λογικής «πότε ρωτάμε / τι επιλέγουμε αυτόματα».
enum BackupZipCandidateSelectionKind {
  /// Κανένας έγκυρος υποψήφιος — αποτυχία με μήνυμα.
  none,

  /// Ακριβώς ένας — αυτόματη επιλογή χωρίς διάλογο.
  automatic,

  /// Δύο ή περισσότεροι — υποχρεωτική ερώτηση χρήστη.
  requiresChoice,
}

/// Απόφαση επιλογής υποψηφίου βάσης μέσα σε απογραφή `.zip`.
class BackupZipCandidateSelection {
  const BackupZipCandidateSelection._({
    required this.kind,
    this.selected,
    this.failureMessage,
  });

  const BackupZipCandidateSelection.none(String failureMessage)
      : this._(
          kind: BackupZipCandidateSelectionKind.none,
          failureMessage: failureMessage,
        );

  const BackupZipCandidateSelection.automatic(
    BackupZipEligibleCandidate selected,
  ) : this._(
          kind: BackupZipCandidateSelectionKind.automatic,
          selected: selected,
        );

  const BackupZipCandidateSelection.requiresChoice()
      : this._(kind: BackupZipCandidateSelectionKind.requiresChoice);

  final BackupZipCandidateSelectionKind kind;
  final BackupZipEligibleCandidate? selected;
  final String? failureMessage;

  bool get requiresUserChoice =>
      kind == BackupZipCandidateSelectionKind.requiresChoice;
}

/// Καθαρή λογική επιλογής: 0 → αποτυχία, 1 → αυτόματα, ≥2 → ερώτηση.
BackupZipCandidateSelection decideBackupZipCandidateSelection(
  BackupZipInventory inventory,
) {
  final eligible = inventory.eligibleCandidates;
  if (eligible.isEmpty) {
    return BackupZipCandidateSelection.none(
      _noneFailureMessage(inventory),
    );
  }
  if (eligible.length == 1) {
    return BackupZipCandidateSelection.automatic(eligible.single);
  }
  return const BackupZipCandidateSelection.requiresChoice();
}

String _noneFailureMessage(BackupZipInventory inventory) {
  final total = inventory.totalDatabaseEntries;
  if (total == 0) {
    return 'Δεν βρέθηκε αρχείο βάσης (.db) μέσα στο zip.';
  }

  final buffer = StringBuffer(
    'Βρέθηκαν $total αρχεία βάσης, κανένα δεν είναι έγκυρη βάση '
    'της εφαρμογής',
  );
  if (inventory.rejectedCandidates.isEmpty) {
    buffer.write('.');
    return buffer.toString();
  }

  buffer.write(': ');
  buffer.write(
    inventory.rejectedCandidates
        .map((r) => '${r.displayName} (${r.reason})')
        .join(', '),
  );
  buffer.write('.');
  return buffer.toString();
}
