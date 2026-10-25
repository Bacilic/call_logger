// Οι λίστες επιλογής της φόρμας κλήσης ακολουθούν τη μία σειρά κειμένου της
// εφαρμογής: τόνοι και κεφαλαία δεν μετρούν, αριθμοί με φυσική σειρά.
//
//   flutter test test/core/services/lookup_service_sort_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _dept = 1;

UserModel _user(int id, String first, String last) =>
    UserModel(id: id, firstName: first, lastName: last, departmentId: _dept);

void _inject({
  List<UserModel> users = const [],
  List<DepartmentModel> departments = const [],
}) {
  LookupService.instance
    ..resetForReload()
    ..injectInMemoryCatalogForTests(
      users: users,
      equipment: const [],
      departmentRows: departments,
    );
}

void main() {
  test('υπάλληλοι τμήματος: η «Όλγα» μπαίνει στο Ο, όχι πρώτη', () {
    _inject(
      users: [
        _user(1, 'Όλγα', 'Ζαχαρίου'),
        _user(2, 'Ήρα', 'Κωστάκη'),
        _user(3, 'Αθανάσιος', 'Βλάχος'),
      ],
      departments: [DepartmentModel(id: _dept, name: 'Φαρμακείο')],
    );

    final names = LookupService.instance
        .getUsersByDepartment(_dept)
        .map((u) => u.firstName)
        .toList();

    expect(names, ['Αθανάσιος', 'Ήρα', 'Όλγα']);
  });

  test('τμήματα: το «Έκτακτα» μπαίνει στο Ε, όχι πριν από το Α', () {
    _inject(
      departments: [
        DepartmentModel(id: 1, name: 'Έκτακτα'),
        DepartmentModel(id: 2, name: 'Αιματολογικό'),
        DepartmentModel(id: 3, name: 'Ζ Παθολογική'),
      ],
    );

    final names = LookupService.instance
        .searchDepartments('')
        .map((d) => d.name)
        .toList();

    expect(names, ['Αιματολογικό', 'Έκτακτα', 'Ζ Παθολογική']);
  });
}
