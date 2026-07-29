// Καθαρή λογική μηνυμάτων διαγραφής υπαλλήλου (χωρίς widgets/βάση).

/// Εμφάνιση ονόματος με προαιρετικό τμήμα: `Όνομα (Τμήμα)` ή μόνο `Όνομα`.
String employeeDisplayLabel(String name, String? departmentName) {
  final n = name.trim();
  final displayName = n.isEmpty ? '?' : n;
  final dept = departmentName?.trim() ?? '';
  if (dept.isEmpty) return displayName;
  return '$displayName ($dept)';
}

/// Τίτλος διαλόγου επιβεβαίωσης διαγραφής.
String userDeletionConfirmTitle(int count) {
  if (count == 1) return 'Διαγραφή υπαλλήλου';
  return 'Διαγραφή υπαλλήλων';
}

/// Περιεχόμενο διαλόγου επιβεβαίωσης.
///
/// [labels] είναι ήδη μορφής `Όνομα` ή `Όνομα (Τμήμα)`.
String userDeletionConfirmMessage(List<String> labels) {
  final count = labels.length;
  if (count <= 0) return 'Διαγραφή υπαλλήλων;';
  if (count == 1) {
    return 'Διαγραφή υπαλλήλου «${labels.first}»;';
  }
  if (count <= 5) {
    final buf = StringBuffer('Διαγραφή $count υπαλλήλων:');
    for (final label in labels) {
      buf.write('\n• $label');
    }
    return buf.toString();
  }
  return 'Διαγραφή $count υπαλλήλων;';
}

/// Τι ακυρώνεται συνολικά αν ο χρήστης πατήσει «Ακύρωση» στη μέση της ροής.
///
/// Μπαίνει στο μήνυμα του διαλόγου ακύρωσης: «Θα ακυρωθεί <αυτό>.»
String userDeletionCancelScopeDescription(int userCount) {
  if (userCount <= 1) return 'η διαγραφή του υπαλλήλου';
  return 'η διαγραφή $userCount υπαλλήλων';
}

/// Επιβεβαίωση ότι όντως δεν έγινε τίποτα — η ακύρωση δεν μένει σιωπηλή.
String userDeletionCancelledMessage(int userCount) {
  if (userCount <= 1) {
    return 'Η διαγραφή ακυρώθηκε. Δεν άλλαξε τίποτα.';
  }
  return 'Η διαγραφή $userCount υπαλλήλων ακυρώθηκε. Δεν άλλαξε τίποτα.';
}

/// Μία ενέργεια αποδέσμευσης στοιχείου για το snackbar σύνοψης.
enum UserDeletionAssetActionKind { keep, transfer, delete }

class UserDeletionAssetAction {
  const UserDeletionAssetAction({
    required this.kind,
    required this.identifier,
    required this.isPhone,
  });

  final UserDeletionAssetActionKind kind;
  final String identifier;
  final bool isPhone;
}

String _assetActionVerb(UserDeletionAssetActionKind kind) {
  switch (kind) {
    case UserDeletionAssetActionKind.keep:
      return 'παραμονή';
    case UserDeletionAssetActionKind.transfer:
      return 'μετακίνηση';
    case UserDeletionAssetActionKind.delete:
      return 'διαγραφή';
  }
}

String _assetActionNoun({required bool isPhone, required bool plural}) {
  if (isPhone) {
    return plural ? 'τηλεφώνων' : 'τηλεφώνου';
  }
  return plural ? 'εξοπλισμών' : 'εξοπλισμού';
}

/// Snackbar σύνοψης μετά τη διαγραφή.
///
/// Παράδειγμα:
/// `Διαγράφηκε Αναστασία Φούφα · μετακίνηση τηλεφώνου (2896) · διαγραφή εξοπλισμού (3874)`
String userDeletionSummaryMessage({
  required List<String> employeeNames,
  required List<UserDeletionAssetAction> assetActions,
}) {
  final names = employeeNames
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .toList();
  final namePart = names.isEmpty
      ? 'Διαγράφηκαν υπάλληλοι'
      : (names.length == 1
            ? 'Διαγράφηκε ${names.first}'
            : 'Διαγράφηκαν ${names.join(', ')}');

  if (assetActions.isEmpty) {
    return namePart;
  }

  final parts = <String>[namePart];
  for (final action in assetActions) {
    final id = action.identifier.trim();
    if (id.isEmpty) continue;
    final verb = _assetActionVerb(action.kind);
    final noun = _assetActionNoun(isPhone: action.isPhone, plural: false);
    parts.add('$verb $noun ($id)');
  }
  return parts.join(' · ');
}
