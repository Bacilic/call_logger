// Καθαρή λογική μηνυμάτων διαγραφής υπαλλήλου (χωρίς widgets/βάση).

import 'bulk_deletion_summary.dart';

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

/// Σύνοψη της πράξης: πόσοι υπάλληλοι και πόσα στοιχεία θα ζητήσουν απόφαση.
///
/// Με λίγους υπαλλήλους ο κατάλογος ονομάτων αρκεί· με πολλούς ο χρήστης
/// χρειάζεται να ξέρει και **πόσες ερωτήσεις** τον περιμένουν, γιατί η ροή
/// συνεχίζεται με έναν διάλογο ανά τηλέφωνο και ανά εξοπλισμό.
String userDeletionHeadline({
  required int userCount,
  required int exclusivePhoneCount,
  required int exclusiveEquipmentCount,
  int? initiallySelected,
}) {
  return buildBulkDeletionHeadline(
    subject: SummaryCount(userCount, 'υπάλληλος', 'υπάλληλοι'),
    initiallySelected: initiallySelected,
    details: [
      SummaryCount(
        exclusivePhoneCount,
        'προσωπικό τηλέφωνο',
        'προσωπικά τηλέφωνα',
      ),
      SummaryCount(
        exclusiveEquipmentCount,
        'προσωπικός εξοπλισμός',
        'προσωπικοί εξοπλισμοί',
      ),
    ],
  );
}

/// Προειδοποίηση ότι η ροή δεν τελειώνει με το κουμπί «Διαγραφή».
///
/// Επιστρέφει `null` όταν δεν υπάρχει τίποτα να ρωτηθεί — τότε η διαγραφή είναι
/// όντως ένα κλικ και η προειδοποίηση θα ήταν ψέμα.
String? userDeletionPendingQuestionsNotice(int assetCount) {
  if (assetCount <= 0) return null;
  if (assetCount == 1) {
    return 'Θα σας ζητηθεί απόφαση για 1 στοιχείο πριν ολοκληρωθεί η διαγραφή.';
  }
  return 'Θα σας ζητηθεί απόφαση για $assetCount στοιχεία πριν ολοκληρωθεί '
      'η διαγραφή.';
}

/// Τι ακυρώνεται συνολικά αν ο χρήστης πατήσει «Ακύρωση» στη μέση της ροής.
///
/// Μπαίνει στο μήνυμα του διαλόγου ακύρωσης: «Θα ακυρωθεί <αυτό>.»
String userDeletionCancelScopeDescription(int userCount) {
  if (userCount <= 1) return 'η διαγραφή του υπαλλήλου';
  return 'η διαγραφή $userCount υπαλλήλων';
}

/// Τι έχει ολοκληρωθεί μέχρι στιγμής — πρώτη γραμμή του διαλόγου διακοπής.
///
/// «Ολοκληρωμένος» είναι ο υπάλληλος που έχει απαντηθεί **και** για τα
/// τηλέφωνά του **και** για τον εξοπλισμό του — γι' αυτό η συλλογή τρέχει έναν
/// γύρο ανά υπάλληλο και όχι έναν γύρο ανά είδος στοιχείου.
String userDeletionCompletedSummary({
  required int completed,
  required int total,
}) {
  return completed == 1
      ? 'Ολοκληρώσατε 1 υπάλληλο από τους $total.'
      : 'Ολοκληρώσατε $completed υπαλλήλους από τους $total.';
}

/// Υπόδειξη του κουμπιού «Εφαρμογή απαντήσεων» — αυτοτελής πρόταση.
String userDeletionApplyCompletedHint(int completed) {
  return completed == 1
      ? 'Κλείνει ο οδηγός και διαγράφεται ο 1 υπάλληλος που ολοκληρώσατε. Οι '
            'υπόλοιποι μένουν ανέγγιχτοι και επιλεγμένοι.'
      : 'Κλείνει ο οδηγός και διαγράφονται οι $completed υπάλληλοι που '
            'ολοκληρώσατε. Οι υπόλοιποι μένουν ανέγγιχτοι και επιλεγμένοι.';
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

/// Προειδοποίηση ότι η διαγραφή άφησε τμήμα χωρίς κανένα εξάρτημα.
///
/// Επιστρέφει `null` όταν δεν άδειασε κανένα — δεν υπάρχει λόγος να
/// προστεθεί σιωπή στο μήνυμα. Δεν είναι απαγόρευση ούτε σφάλμα: ένα τμήμα
/// μπορεί να αδειάσει θεμιτά, απλώς αξίζει να το ξέρει ο χρήστης όσο έχει
/// φρέσκο το πλαίσιο στο μυαλό του.
String? emptiedDepartmentsNotice(List<String> departmentNames) {
  final names = departmentNames
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .toList();
  if (names.isEmpty) return null;
  if (names.length == 1) {
    return 'Το τμήμα «${names.first}» έμεινε χωρίς κανένα εξάρτημα';
  }
  final quoted = names.map((n) => '«$n»').join(', ');
  return 'Τα τμήματα $quoted έμειναν χωρίς κανένα εξάρτημα';
}

/// Snackbar σύνοψης μετά τη διαγραφή.
///
/// Παράδειγμα:
/// `Διαγράφηκε Αναστασία Φούφα · μετακίνηση τηλεφώνου (2896) · διαγραφή εξοπλισμού (3874)`
///
/// Το [emptiedDepartments] προσαρτάται στο τέλος, μετά τις ενέργειες: είναι
/// συνέπεια της διαγραφής, όχι μέρος της.
String userDeletionSummaryMessage({
  required List<String> employeeNames,
  required List<UserDeletionAssetAction> assetActions,
  List<String> emptiedDepartments = const [],
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

  final parts = <String>[namePart];
  for (final action in assetActions) {
    final id = action.identifier.trim();
    if (id.isEmpty) continue;
    final verb = _assetActionVerb(action.kind);
    final noun = _assetActionNoun(isPhone: action.isPhone, plural: false);
    parts.add('$verb $noun ($id)');
  }

  final emptied = emptiedDepartmentsNotice(emptiedDepartments);
  if (emptied != null) parts.add(emptied);

  return parts.join(' · ');
}
