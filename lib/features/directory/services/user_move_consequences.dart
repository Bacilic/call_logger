import '../models/department_kind.dart';

/// Τι αλλάζει για τον άνθρωπο όταν μετακινείται σε τμήμα άλλου Είδους.
///
/// **Η γραμμή που λέει, όχι φραγή.** Η μετακίνηση ρωτά ήδη δύο φορές — τι
/// γίνονται τα τηλέφωνά του και τι ο εξοπλισμός του — και το αναγνωριστικό
/// Lansweeper έχει δική του ζωντανή υπόδειξη ακριβώς από κάτω. Ό,τι απομένει
/// δεν είναι απόφαση: είναι **γεγονός που δεν λέγεται πουθενά**.
///
/// Δύο πράγματα, ένα ανά κατεύθυνση:
///
/// 1. **Προς Είδος που δεν κρατά μηχανήματα.** Ο εξοπλισμός του θα μείνει
///    πίσω, και η ερώτηση «ακολουθεί ή μένει;» δεν γίνεται καν — σωστά, αλλά
///    σιωπηλά. Η γραμμή το λέει πριν πατηθεί η Αποθήκευση.
/// 2. **Προς τμήμα του νοσοκομείου.** Δεν χάνεται τίποτα, αλλά η καρτέλα
///    αρχίζει να κρίνεται για το αναγνωριστικό της στον Έλεγχο δεδομένων.
///
/// Καθαρή κρίση: καμία πρόσβαση σε βάση, κανένα widget.
class UserMoveConsequences {
  const UserMoveConsequences({
    this.equipmentLeftBehind = 0,
    this.startsExpectingLansweeper = false,
  });

  /// Τίποτα προς αναγγελία — η συνηθισμένη περίπτωση.
  static const none = UserMoveConsequences();

  /// Πόσα μηχανήματα δεν μπορούν να ακολουθήσουν τον άνθρωπο.
  final int equipmentLeftBehind;

  /// Επιστρέφει σε τμήμα του νοσοκομείου χωρίς αναγνωριστικό Lansweeper.
  final bool startsExpectingLansweeper;

  bool get hasAnything => equipmentLeftBehind > 0 || startsExpectingLansweeper;
}

/// Τι θα αλλάξει, δεδομένου του τμήματος στο οποίο πάει ο υπάλληλος.
///
/// Όπως και στην αλλαγή Είδους μιας καρτέλας, η κρίση μιλά για **μεταβάσεις**:
/// υπάλληλος που ήταν ήδη σε εταιρεία και πάει σε άλλη δεν «χάνει» τώρα τον
/// εξοπλισμό του — τον είχε ήδη χάσει.
///
/// Το [lansweeperIsEmpty] κρίνεται πάνω στο **πεδίο** της φόρμας: ο χρήστης
/// μπορεί να συμπληρώνει το αναγνωριστικό την ίδια στιγμή που αλλάζει τμήμα,
/// και η γραμμή δεν πρέπει να του ζητά κάτι που μόλις έγραψε.
UserMoveConsequences judgeUserMove({
  required DepartmentKind previousKind,
  required DepartmentKind targetKind,
  required int carriedEquipmentCount,
  required bool lansweeperIsEmpty,
}) {
  if (previousKind == targetKind) return UserMoveConsequences.none;

  final losesEquipment =
      previousKind.canOwnEquipment && !targetKind.canOwnEquipment;
  final startsExpectingLansweeper =
      !previousKind.participatesInLansweeper &&
      targetKind.participatesInLansweeper;

  return UserMoveConsequences(
    equipmentLeftBehind: losesEquipment ? carriedEquipmentCount : 0,
    startsExpectingLansweeper: startsExpectingLansweeper && lansweeperIsEmpty,
  );
}

/// Η γραμμή κάτω από το «Τμήμα» — `null` όταν δεν υπάρχει τίποτα να ειπωθεί.
///
/// Μία γραμμή που εμφανίζεται πάντα παύει να διαβάζεται.
String? userMoveConsequencesMessage({
  required DepartmentKind targetKind,
  required UserMoveConsequences consequences,
}) {
  if (!consequences.hasAnything) return null;

  final parts = <String>[
    if (consequences.equipmentLeftBehind > 0)
      _equipmentPhrase(
        count: consequences.equipmentLeftBehind,
        kind: targetKind,
      ),
    if (consequences.startsExpectingLansweeper)
      'Ως υπάλληλος του νοσοκομείου θα ζητηθεί αναγνωριστικό Lansweeper — όσο '
          'λείπει, θα εμφανίζεται στον Έλεγχο δεδομένων.',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Βγάζει αυτή η μετακίνηση τον άνθρωπο **έξω από το νοσοκομείο**;
///
/// **Μιλά για μετάβαση, όχι για κατάσταση.** Υπάλληλος που ήταν ήδη σε
/// εταιρεία και πάει σε άλλη δεν φεύγει τώρα από τον οργανισμό — έχει ήδη
/// φύγει, και μια προειδοποίηση εκεί θα ήταν θόρυβος. Ίδιος κανόνας με την
/// [judgeUserMove] ακριβώς από πάνω.
bool userLeavesHospital({
  required DepartmentKind previousKind,
  required DepartmentKind targetKind,
}) {
  return previousKind.belongsToHospital && !targetKind.belongsToHospital;
}

/// Η πρόταση που το λέει, με το όνομα του ανθρώπου μέσα.
///
/// **Γιατί ονομάζει τον άνθρωπο:** η επιβεβαίωση γίνεται συνήθως αφού ο
/// χειριστής έχει ήδη αποφασίσει, και το όνομα είναι το μόνο που τον κάνει να
/// ξανακοιτάξει. «Ο Αντώνης φεύγει από το νοσοκομείο» διαβάζεται· ένα «η
/// μετακίνηση αφορά εξωτερικό φορέα» προσπερνιέται.
///
/// `null` όταν δεν υπάρχει έξοδος — η πρόταση δεν εμφανίζεται ποτέ «απλώς για
/// σιγουριά»: μια γραμμή που βγαίνει πάντα παύει να διαβάζεται.
String? userLeavesHospitalMessage({
  required DepartmentKind previousKind,
  required DepartmentKind targetKind,
  required String targetDepartmentName,
  String? userDisplayName,
}) {
  if (!userLeavesHospital(previousKind: previousKind, targetKind: targetKind)) {
    return null;
  }

  final name = userDisplayName?.trim() ?? '';
  final where = targetDepartmentName.trim();
  final what = targetKind.entityWithArticle;
  final place = where.isEmpty ? what : '$what «$where»';

  return name.isEmpty
      ? 'Προσοχή: $place δεν ανήκει στο νοσοκομείο — ο υπάλληλος παύει να '
            'είναι εσωτερικός.'
      : 'Προσοχή: $place δεν ανήκει στο νοσοκομείο — ο/η $name παύει να είναι '
            'εσωτερικός υπάλληλος.';
}

/// Η ίδια πρόταση για **πολλούς** ανθρώπους μαζί, στη μαζική μεταφορά.
///
/// Ξεχωριστή από τη μονή επειδή εκεί δεν υπάρχει ένα όνομα να ειπωθεί, και
/// το πλήθος είναι ακριβώς αυτό που πρέπει να τρομάξει: άλλο «ο Αντώνης
/// φεύγει», άλλο «δώδεκα άνθρωποι φεύγουν».
String? usersLeaveHospitalMessage({
  required DepartmentKind targetKind,
  required String targetDepartmentName,
  required int count,
}) {
  if (targetKind.belongsToHospital || count <= 0) return null;

  final where = targetDepartmentName.trim();
  final what = targetKind.entityWithArticle;
  final place = where.isEmpty ? what : '$what «$where»';

  return count == 1
      ? 'Προσοχή: $place δεν ανήκει στο νοσοκομείο — 1 υπάλληλος παύει να '
            'είναι εσωτερικός.'
      : 'Προσοχή: $place δεν ανήκει στο νοσοκομείο — $count υπάλληλοι παύουν '
            'να είναι εσωτερικοί.';
}

String _equipmentPhrase({required int count, required DepartmentKind kind}) {
  // Το «μένει στο τμήμα που αφήνει» λέει ακριβώς πού καταλήγει — ένα σκέτο
  // «δεν ακολουθεί» θα άφηνε τον χρήστη να αναρωτιέται αν χάθηκε. Οι δύο
  // φράσεις γράφονται ολόκληρες: αλλάζουν και τα δύο ρήματα μαζί με τον
  // αριθμό, όχι μόνο το πρώτο.
  return count == 1
      ? '1 μηχάνημα δεν μπορεί να ακολουθήσει ${kind.entityWhere} — μένει '
            'στο τμήμα που αφήνει'
      : '$count μηχανήματα δεν μπορούν να ακολουθήσουν ${kind.entityWhere} — '
            'μένουν στο τμήμα που αφήνει';
}
