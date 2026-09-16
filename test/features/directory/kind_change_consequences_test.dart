// Τι λέει η φόρμα τη στιγμή που αλλάζει το Είδος μιας καρτέλας.
//
// Η γραμμή μιλά για ΜΕΤΑΒΑΣΕΙΣ: ανακοινώνει μόνο ό,τι αλλάζει κατάσταση τώρα.
// Μια εταιρεία που γίνεται εξωτερική μονάδα δεν χάνει τα αναγνωριστικά της —
// τα είχε ήδη χαμένα, και μια αναγγελία θα έλεγε ψέματα με σωστά νούμερα.
//
// Η κάτοψη λείπει σκόπιμα: έχει ήδη τον δικό της διάλογο στην αποθήκευση.
//
//   flutter test test/features/directory/kind_change_consequences_test.dart

import 'package:call_logger/features/directory/models/department_kind.dart';
import 'package:call_logger/features/directory/services/kind_change_consequences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  KindChangeConsequences judge({
    required DepartmentKind from,
    required DepartmentKind to,
    int accounts = 0,
    int employees = 0,
    int employeeAccounts = 0,
    bool buildingIsEmpty = false,
  }) => judgeKindChange(
    previousKind: from,
    selectedKind: to,
    departmentLansweeperAccounts: accounts,
    employeesInDepartment: employees,
    employeesWithLansweeperAccount: employeeAccounts,
    buildingIsEmpty: buildingIsEmpty,
  );

  String? message(DepartmentKind kind, KindChangeConsequences consequences) =>
      kindChangeConsequencesMessage(
        selectedKind: kind,
        consequences: consequences,
      );

  group('Πότε δεν λέγεται τίποτα', () {
    test('ίδιο Είδος: καμία αλλαγή', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.hospital,
        accounts: 3,
        employees: 5,
      );

      expect(result.hasAnything, isFalse);
      expect(message(DepartmentKind.hospital, result), isNull);
    });

    test('άδεια καρτέλα προς εταιρεία: τίποτα να χαθεί', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
      );

      expect(message(DepartmentKind.company, result), isNull);
    });

    test('εταιρεία προς εξωτερική μονάδα: τα είχε ήδη χαμένα', () {
      final result = judge(
        from: DepartmentKind.company,
        to: DepartmentKind.externalUnit,
        accounts: 2,
        employees: 3,
        employeeAccounts: 2,
      );

      expect(
        message(DepartmentKind.externalUnit, result),
        isNull,
        reason:
            'Η εταιρεία δεν συμμετείχε ποτέ στο Lansweeper — τίποτα δεν παύει '
            'να ισχύει τώρα.',
      );
    });

    test('επιστροφή σε τμήμα ΜΕ κτίριο: τίποτα', () {
      final result = judge(
        from: DepartmentKind.company,
        to: DepartmentKind.hospital,
      );

      expect(message(DepartmentKind.hospital, result), isNull);
    });
  });

  group('Προς Είδος εκτός Lansweeper', () {
    test('αναγνωριστικά τμήματος και υπάλληλοι μαζί', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
        accounts: 2,
        employees: 3,
        employeeAccounts: 2,
      );

      expect(
        message(DepartmentKind.company, result),
        '2 αναγνωριστικά Lansweeper παύουν να ισχύουν, αλλά μένουν '
        'αποθηκευμένα · 3 υπάλληλοι μένουν στην εταιρεία και τα 2 δικά τους '
        'αναγνωριστικά παύουν να ισχύουν',
      );
    });

    test('ένα αναγνωριστικό, ένας υπάλληλος: ενικός παντού', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
        accounts: 1,
        employees: 1,
        employeeAccounts: 1,
      );

      expect(
        message(DepartmentKind.company, result),
        '1 αναγνωριστικό Lansweeper παύει να ισχύει, αλλά μένει αποθηκευμένο · '
        '1 υπάλληλος μένει στην εταιρεία και το δικό του αναγνωριστικό παύει '
        'να ισχύει',
      );
    });

    test('υπάλληλοι χωρίς αναγνωριστικά: μόνο πού μένουν', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.company,
        employees: 4,
      );

      expect(
        message(DepartmentKind.company, result),
        '4 υπάλληλοι μένουν στην εταιρεία',
      );
    });

    test('εξωτερική μονάδα: δικό της άρθρο', () {
      final result = judge(
        from: DepartmentKind.hospital,
        to: DepartmentKind.externalUnit,
        employees: 2,
      );

      expect(
        message(DepartmentKind.externalUnit, result),
        '2 υπάλληλοι μένουν στην εξωτερική μονάδα',
      );
    });
  });

  group('Η αντίστροφη φορά', () {
    test('επιστροφή σε τμήμα ΧΩΡΙΣ κτίριο: το λέει', () {
      final result = judge(
        from: DepartmentKind.company,
        to: DepartmentKind.hospital,
        buildingIsEmpty: true,
      );

      expect(
        message(DepartmentKind.hospital, result),
        'Ως τμήμα του νοσοκομείου η καρτέλα ζητά κτίριο — όσο λείπει, θα '
        'εμφανίζεται στον Έλεγχο δεδομένων.',
      );
    });

    test('εταιρεία προς εξωτερική μονάδα: καμία απαίτηση κτιρίου', () {
      final result = judge(
        from: DepartmentKind.company,
        to: DepartmentKind.externalUnit,
        buildingIsEmpty: true,
      );

      expect(
        result.startsExpectingBuilding,
        isFalse,
        reason: 'Ούτε η εξωτερική μονάδα ζητά κτίριο του νοσοκομείου.',
      );
    });

    test('η επιστροφή δεν ανακοινώνει απώλειες', () {
      final result = judge(
        from: DepartmentKind.company,
        to: DepartmentKind.hospital,
        accounts: 2,
        employees: 3,
        employeeAccounts: 2,
        buildingIsEmpty: true,
      );

      expect(result.departmentLansweeperAccounts, 0);
      expect(result.employeesStaying, 0);
      expect(
        message(DepartmentKind.hospital, result),
        contains('ζητά κτίριο'),
        reason:
            'Προς τα εκεί τίποτα δεν παύει — μόνο μια απαίτηση προστίθεται.',
      );
    });
  });
}
