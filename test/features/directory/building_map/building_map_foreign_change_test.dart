// Unit tests: ο χάρτης αναγνωρίζει αλλαγή άλλου σταθμού που δεν έχει δει.
//
//   flutter test test/features/directory/building_map/building_map_foreign_change_test.dart

import 'package:call_logger/features/directory/building_map/services/building_map_foreign_change.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _placement = [
  'map_floor',
  'floor_id',
  'map_x',
  'map_y',
  'map_width',
  'map_height',
  'map_rotation',
];

Map<String, Object?> _cardiologyOnSecond() => {
  'id': 7,
  'name': 'Καρδιολογική',
  'color': '#1976D2',
  'floor_id': 2,
  'map_floor': '2',
  'map_x': 10.0,
  'map_y': 20.0,
  'map_width': 30.0,
  'map_height': 40.0,
  'map_rotation': 0.0,
  'map_hidden': 0,
  'is_deleted': 0,
};

void main() {
  test('ο POPINIO έβγαλε την Καρδιολογική από τον 2ο: διένεξη', () {
    final seen = DepartmentModel.fromMap(_cardiologyOnSecond());
    final fresh = {
      ..._cardiologyOnSecond(),
      'floor_id': null,
      'map_floor': null,
      'map_x': 0.0,
      'map_y': 0.0,
      'map_width': 0.0,
      'map_height': 0.0,
    };

    final conflict = buildingMapForeignChange(
      seen: seen,
      freshRow: fresh,
      columns: _placement,
    );

    expect(conflict, isNotNull);
    expect(conflict!.changedKeys, containsAll(['map_floor', 'map_width']));
  });

  test('κανείς δεν άλλαξε τίποτα: καμία ερώτηση', () {
    final seen = DepartmentModel.fromMap(_cardiologyOnSecond());

    expect(
      buildingMapForeignChange(
        seen: seen,
        freshRow: _cardiologyOnSecond(),
        columns: _placement,
      ),
      isNull,
    );
  });

  test('κενή περιστροφή στη βάση = 0 στον χάρτη: δεν είναι διένεξη', () {
    final seen = DepartmentModel.fromMap(_cardiologyOnSecond());

    expect(
      buildingMapForeignChange(
        seen: seen,
        freshRow: {..._cardiologyOnSecond(), 'map_rotation': null},
        columns: _placement,
      ),
      isNull,
    );
  });

  test('το μήνυμα ονομάζει χρήστη, τμήμα και ώρα', () {
    expect(
      buildingMapConflictHeadline(
        departmentName: 'Γραφείο Κίνησης',
        changedBy: 'Βασίλης',
        changedAt: DateTime(2026, 10, 17, 15, 4),
        now: DateTime(2026, 10, 17, 15, 6),
      ),
      'Ο χρήστης «Βασίλης» άλλαξε τη σχεδίαση του τμήματος '
      '«Γραφείο Κίνησης» στις 15:04.',
    );
  });

  test('αλλαγή σε στήλη που η ενέργεια δεν γράφει: καμία ερώτηση', () {
    final seen = DepartmentModel.fromMap(_cardiologyOnSecond());

    expect(
      buildingMapForeignChange(
        seen: seen,
        freshRow: {..._cardiologyOnSecond(), 'map_custom_name': 'Καρδιο'},
        columns: _placement,
      ),
      isNull,
    );
  });
}
