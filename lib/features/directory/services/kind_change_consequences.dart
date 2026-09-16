import '../models/department_kind.dart';

/// Τι παύει και τι αρχίζει να ισχύει όταν αλλάζει το Είδος μιας καρτέλας.
///
/// **Η γραμμή που λείπει, όχι τρίτος διάλογος.** Η αλλαγή Είδους ρωτά ήδη δύο
/// φορές — για τη θέση στην κάτοψη και για κάθε μηχάνημα που δεν επιτρέπεται
/// να μείνει. Ό,τι απομένει **δεν χάνεται**: τα αναγνωριστικά Lansweeper μένουν
/// γραμμένα και επιστρέφουν αν η καρτέλα ξαναγίνει τμήμα, και οι υπάλληλοι
/// μένουν στη θέση τους. Άρα δεν δικαιολογείται φραγή — δικαιολογείται να
/// **λέγεται**, τη στιγμή που ο χρήστης διαλέγει.
///
/// Γι' αυτό η κάτοψη λείπει σκόπιμα από εδώ: έχει ήδη τον δικό της διάλογο, και
/// η επανάληψη θα έκανε τη γραμμή θόρυβο αντί για πληροφορία.
///
/// Καθαρή κρίση: καμία πρόσβαση σε βάση, κανένα widget.
class KindChangeConsequences {
  const KindChangeConsequences({
    this.departmentLansweeperAccounts = 0,
    this.employeesStaying = 0,
    this.employeeLansweeperAccounts = 0,
    this.startsExpectingBuilding = false,
  });

  /// Τίποτα προς αναγγελία — η συνηθισμένη περίπτωση.
  static const none = KindChangeConsequences();

  /// Πόσα αναγνωριστικά Lansweeper της ίδιας της καρτέλας παύουν να ισχύουν.
  final int departmentLansweeperAccounts;

  /// Πόσοι υπάλληλοι θα βρεθούν κάτω από το νέο Είδος.
  final int employeesStaying;

  /// Πόσων υπαλλήλων τα αναγνωριστικά Lansweeper παύουν να ισχύουν.
  final int employeeLansweeperAccounts;

  /// Η αντίστροφη φορά: η καρτέλα γίνεται τμήμα του νοσοκομείου και αρχίζει
  /// να ζητά κτίριο — όσο λείπει, εμφανίζεται στον Έλεγχο δεδομένων.
  final bool startsExpectingBuilding;

  bool get hasAnything =>
      departmentLansweeperAccounts > 0 ||
      employeesStaying > 0 ||
      startsExpectingBuilding;
}

/// Τι θα αλλάξει, δεδομένου του Είδους που μόλις επιλέχθηκε.
///
/// Χωρίς αλλαγή Είδους δεν υπάρχει τίποτα να πει κανείς: η κρίση επιστρέφει
/// [KindChangeConsequences.none] και η φόρμα μένει σιωπηλή.
///
/// Το [buildingIsEmpty] κρίνεται από τον καλούντα πάνω στο **πεδίο της φόρμας**
/// και όχι στην αποθηκευμένη τιμή: ο χρήστης μπορεί να συμπληρώνει κτίριο την
/// ίδια στιγμή που γυρίζει το Είδος, και η γραμμή δεν πρέπει να του ζητά κάτι
/// που μόλις έγραψε.
KindChangeConsequences judgeKindChange({
  required DepartmentKind previousKind,
  required DepartmentKind selectedKind,
  required int departmentLansweeperAccounts,
  required int employeesInDepartment,
  required int employeesWithLansweeperAccount,
  required bool buildingIsEmpty,
}) {
  if (previousKind == selectedKind) return KindChangeConsequences.none;

  // **Η γραμμή μιλά για ΜΕΤΑΒΑΣΕΙΣ, όχι για την τελική κατάσταση.** Μια
  // εταιρεία που γίνεται εξωτερική μονάδα δεν χάνει τα αναγνωριστικά της: τα
  // είχε ήδη χαμένα. Χωρίς αυτή τη διάκριση η γραμμή θα ανήγγειλλε ως καινούργιο
  // κάτι που ίσχυε ήδη — δηλαδή θα έλεγε ψέματα με σωστά νούμερα.
  final losesLansweeper =
      previousKind.participatesInLansweeper &&
      !selectedKind.participatesInLansweeper;
  final startsExpectingBuilding =
      !previousKind.expectsHospitalBuilding &&
      selectedKind.expectsHospitalBuilding;

  return KindChangeConsequences(
    // Ό,τι μετριέται εδώ **επιβιώνει** της αλλαγής: τα αναγνωριστικά μένουν
    // γραμμένα και οι υπάλληλοι στη θέση τους. Μετριούνται για να ειπωθούν, όχι
    // για να σβηστούν.
    departmentLansweeperAccounts: losesLansweeper
        ? departmentLansweeperAccounts
        : 0,
    employeesStaying: losesLansweeper ? employeesInDepartment : 0,
    employeeLansweeperAccounts: losesLansweeper
        ? employeesWithLansweeperAccount
        : 0,
    startsExpectingBuilding: startsExpectingBuilding && buildingIsEmpty,
  );
}

/// Η γραμμή κάτω από το «Είδος» — απαριθμεί **μόνο ό,τι υπάρχει**.
///
/// Επιστρέφει `null` όταν δεν υπάρχει τίποτα να ειπωθεί: μια γραμμή που
/// εμφανίζεται πάντα παύει να διαβάζεται.
String? kindChangeConsequencesMessage({
  required DepartmentKind selectedKind,
  required KindChangeConsequences consequences,
}) {
  if (!consequences.hasAnything) return null;

  if (consequences.startsExpectingBuilding) {
    return 'Ως τμήμα του νοσοκομείου η καρτέλα ζητά κτίριο — όσο λείπει, θα '
        'εμφανίζεται στον Έλεγχο δεδομένων.';
  }

  final parts = <String>[
    if (consequences.departmentLansweeperAccounts > 0)
      _accountsPhrase(consequences.departmentLansweeperAccounts),
    if (consequences.employeesStaying > 0)
      _employeesPhrase(
        employees: consequences.employeesStaying,
        withAccounts: consequences.employeeLansweeperAccounts,
        kind: selectedKind,
      ),
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

String _accountsPhrase(int count) {
  // Τα αναγνωριστικά δεν σβήνονται: το «παύει να ισχύει» λέει ακριβώς αυτό που
  // συμβαίνει, και η συνέχεια εξηγεί ότι είναι αναστρέψιμο. Οι δύο φράσεις
  // γράφονται ολόκληρες — το ρήμα και το άρθρο αλλάζουν μαζί με τον αριθμό.
  return count == 1
      ? '1 αναγνωριστικό Lansweeper παύει να ισχύει, αλλά μένει αποθηκευμένο'
      : '$count αναγνωριστικά Lansweeper παύουν να ισχύουν, αλλά μένουν '
            'αποθηκευμένα';
}

String _employeesPhrase({
  required int employees,
  required int withAccounts,
  required DepartmentKind kind,
}) {
  final who = employees == 1
      ? '1 υπάλληλος μένει'
      : '$employees υπάλληλοι μένουν';
  final where = '$who ${kind.entityWhere}';
  if (withAccounts == 0) return where;
  final theirs = withAccounts == 1
      ? 'και το δικό του αναγνωριστικό παύει να ισχύει'
      : 'και τα $withAccounts δικά τους αναγνωριστικά παύουν να ισχύουν';
  return '$where $theirs';
}
