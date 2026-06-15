/// Ορισμοί σενάριων πράσινο (+) → πορτοκαλί (+) για [AssociationTwoStepRunner].
library;

/// Ποιο πεδίο συμπληρώνεται στο δεύτερο βήμα (πορτοκαλί).
enum AssociationOrangeFill {
  phone,
  department,
  equipment,
  none,
}

/// Ένα σενάριο διφασικής καταχώρησης οντότητας από την οθόνη κλήσεων.
class AssociationTwoStepScenario {
  const AssociationTwoStepScenario({
    required this.id,
    required this.title,
    required this.greenPhone,
    required this.greenDepartment,
    required this.greenEquipment,
    required this.orangeFill,
    this.preseedDepartmentName,
    this.updatePrimaryDepartmentOnOrange,
    this.knownBugHint,
  });

  final String id;
  final String title;

  /// Συμπληρωμένα στο πράσινο βήμα (ο καλών είναι πάντα ρητός).
  final bool greenPhone;
  final bool greenDepartment;
  final bool greenEquipment;

  /// Τι προστίθεται πριν το πορτοκαλί βήμα.
  final AssociationOrangeFill orangeFill;

  /// Αν οριστεί, το τμήμα υπάρχει ήδη στη βάση πριν το πράσινο.
  final String? preseedDepartmentName;

  /// Προσομοίωση dialog «Αλλαγή κύριου τμήματος» (μόνο όταν orangeFill == department).
  final bool? updatePrimaryDepartmentOnOrange;

  /// Περιγραφή γνωστού σφάλματος — εμφανίζεται στην αναφορά όταν αποτυγχάνει.
  final String? knownBugHint;

  bool get hasOrangeStep => orangeFill != AssociationOrangeFill.none;

  String phoneFor(String suffix) => '20$suffix';
  String equipmentFor(String suffix) => '10$suffix';
  String callerFor(String suffix) => 'Δοκιμή$suffix';
  String departmentFor(String suffix) => 'Δοκιμαστικό$suffix';
}

/// Πλήρης πίνακας μοτίβων G1–G7 και παραλλαγών dept-exists / dialog.
List<AssociationTwoStepScenario> buildAssociationTwoStepScenarios() {
  return [
    // ── G1: τηλέφωνο + καλών ─────────────────────────────────────────────
    AssociationTwoStepScenario(
      id: 'G1-or-dept-new',
      title: 'G1 τ+υ → δ (νέο τμήμα, dialog Ναι)',
      greenPhone: true,
      greenDepartment: false,
      greenEquipment: false,
      orangeFill: AssociationOrangeFill.department,
      updatePrimaryDepartmentOnOrange: true,
    ),
    AssociationTwoStepScenario(
      id: 'G1-or-dept-no',
      title: 'G1 τ+υ → δ (νέο τμήμα, dialog Όχι)',
      greenPhone: true,
      greenDepartment: false,
      greenEquipment: false,
      orangeFill: AssociationOrangeFill.department,
      updatePrimaryDepartmentOnOrange: false,
      knownBugHint:
          'Μετά πράσινο χωρίς τμήμα, πορτοκαλί με dialog Όχι δεν ενημερώνει τμήμα.',
    ),
    AssociationTwoStepScenario(
      id: 'G1-or-dept-exists',
      title: 'G1 τ+υ → δ (τμήμα υπάρχει στη βάση)',
      greenPhone: true,
      greenDepartment: false,
      greenEquipment: false,
      orangeFill: AssociationOrangeFill.department,
      preseedDepartmentName: 'Δοκιμαστικό1',
      updatePrimaryDepartmentOnOrange: true,
    ),
    AssociationTwoStepScenario(
      id: 'G1-or-equip',
      title: 'G1 τ+υ → ε',
      greenPhone: true,
      greenDepartment: false,
      greenEquipment: false,
      orangeFill: AssociationOrangeFill.equipment,
    ),

    // ── G2: τηλέφωνο + καλών + τμήμα (νέο στο πράσινο) ─────────────────
    AssociationTwoStepScenario(
      id: 'G2-or-equip',
      title: 'G2 τ+υ+δ(νέο) → ε',
      greenPhone: true,
      greenDepartment: true,
      greenEquipment: false,
      orangeFill: AssociationOrangeFill.equipment,
    ),

    // ── G2e: τμήμα υπάρχει ήδη — αναπαραγωγή 2002 ─────────────────────
    AssociationTwoStepScenario(
      id: 'G2e-or-equip',
      title: 'G2e τ+υ+δ(υπάρχον) → ε [2002]',
      greenPhone: true,
      greenDepartment: true,
      greenEquipment: false,
      orangeFill: AssociationOrangeFill.equipment,
      preseedDepartmentName: 'Δοκιμαστικό2',
      // Σημείωση: η διπλή εγγραφή εξοπλισμού (2002) δεν αναπαράγεται στο unit harness·
      // ελέγξτε χειροκίνητα ή με widget test αν χρειάζεται.
    ),

    // ── G3: τηλέφωνο + καλών + εξοπλισμός — αναπαραγωγή 2001 ───────────
    AssociationTwoStepScenario(
      id: 'G3-or-dept-yes',
      title: 'G3 τ+υ+ε → δ (νέο, dialog Ναι) [2001]',
      greenPhone: true,
      greenDepartment: false,
      greenEquipment: true,
      orangeFill: AssociationOrangeFill.department,
      updatePrimaryDepartmentOnOrange: true,
    ),
    AssociationTwoStepScenario(
      id: 'G3-or-dept-no',
      title: 'G3 τ+υ+ε → δ (νέο, dialog Όχι) [2001]',
      greenPhone: true,
      greenDepartment: false,
      greenEquipment: true,
      orangeFill: AssociationOrangeFill.department,
      updatePrimaryDepartmentOnOrange: false,
      knownBugHint:
          'Πορτοκαλί δεν κάνει τίποτα όταν λείπει τμήμα και dialog Όχι — αναπαραγωγή 2001.',
    ),
    AssociationTwoStepScenario(
      id: 'G3-or-dept-exists',
      title: 'G3 τ+υ+ε → δ (υπάρχον τμήμα)',
      greenPhone: true,
      greenDepartment: false,
      greenEquipment: true,
      orangeFill: AssociationOrangeFill.department,
      preseedDepartmentName: 'Δοκιμαστικό3',
      updatePrimaryDepartmentOnOrange: true,
    ),

    // ── G4: καλών + τμήμα (χωρίς τηλέφωνο) ─────────────────────────────
    AssociationTwoStepScenario(
      id: 'G4-or-phone-dept-new',
      title: 'G4 υ+δ(νέο) → τ',
      greenPhone: false,
      greenDepartment: true,
      greenEquipment: false,
      orangeFill: AssociationOrangeFill.phone,
      knownBugHint:
          'updatePhone στο πορτοκαλί καθαρίζει selectedCaller → δεύτερη δημιουργία χρήστη.',
    ),
    AssociationTwoStepScenario(
      id: 'G4e-or-phone',
      title: 'G4e υ+δ(υπάρχον) → τ',
      greenPhone: false,
      greenDepartment: true,
      greenEquipment: false,
      orangeFill: AssociationOrangeFill.phone,
      preseedDepartmentName: 'Δοκιμαστικό4',
      knownBugHint:
          'updatePhone στο πορτοκαλί καθαρίζει selectedCaller → δεύτερη δημιουργία χρήστη.',
    ),

    // ── G5: καλών + τμήμα + εξοπλισμός ─────────────────────────────────
    AssociationTwoStepScenario(
      id: 'G5-or-phone',
      title: 'G5 υ+δ+ε → τ',
      greenPhone: false,
      greenDepartment: true,
      greenEquipment: true,
      orangeFill: AssociationOrangeFill.phone,
      knownBugHint:
          'updatePhone στο πορτοκαλί καθαρίζει selectedCaller → δεύτερη δημιουργία χρήστη.',
    ),

    // ── G6: καλών + εξοπλισμός ─────────────────────────────────────────
    AssociationTwoStepScenario(
      id: 'G6-or-dept',
      title: 'G6 υ+ε → δ',
      greenPhone: false,
      greenDepartment: false,
      greenEquipment: true,
      orangeFill: AssociationOrangeFill.department,
      updatePrimaryDepartmentOnOrange: true,
    ),
    AssociationTwoStepScenario(
      id: 'G6-or-phone',
      title: 'G6 υ+ε → τ',
      greenPhone: false,
      greenDepartment: false,
      greenEquipment: true,
      orangeFill: AssociationOrangeFill.phone,
      knownBugHint:
          'updatePhone στο πορτοκαλί καθαρίζει selectedCaller → δεύτερη δημιουργία χρήστη.',
    ),

    // ── G7: όλα συμπληρωμένα στο πράσινο ───────────────────────────────
    AssociationTwoStepScenario(
      id: 'G7-green-only',
      title: 'G7 τ+υ+δ+ε (μόνο πράσινο)',
      greenPhone: true,
      greenDepartment: true,
      greenEquipment: true,
      orangeFill: AssociationOrangeFill.none,
    ),
  ];
}
