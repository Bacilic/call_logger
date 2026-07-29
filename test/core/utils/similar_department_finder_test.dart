import 'package:call_logger/core/utils/similar_department_finder.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DepartmentModel dept(String name, {int id = 1, bool isDeleted = false}) {
    return DepartmentModel(id: id, name: name, isDeleted: isDeleted);
  }

  group('SimilarDepartmentFinder', () {
    test('Προσωπικού → προτείνει Γραφείο Προσωπικού', () {
      final existing = dept('Γραφείο Προσωπικού', id: 1);
      final found = SimilarDepartmentFinder.findSimilarDepartments(
        departments: [existing],
        typedName: 'Προσωπικού',
      );
      expect(found, hasLength(1));
      expect(found.single.department.name, 'Γραφείο Προσωπικού');
      expect(
        found.single.score,
        greaterThanOrEqualTo(
          SimilarDepartmentFinder.kDepartmentSuggestionMinScore,
        ),
      );
      expect(found.single.score, lessThan(100));
    });

    test('ακριβής ταύτιση εξαιρείται από τα αποτελέσματα', () {
      final existing = dept('Γραφείο Προσωπικού', id: 1);
      final found = SimilarDepartmentFinder.findSimilarDepartments(
        departments: [existing],
        typedName: 'Γραφείο Προσωπικού',
      );
      expect(found, isEmpty);
    });

    test('ακριβής ταύτιση μετά κανονικοποίηση (τόνοι) εξαιρείται', () {
      final existing = dept('Βιοχημικό Τμήμα', id: 1);
      final found = SimilarDepartmentFinder.findSimilarDepartments(
        departments: [existing],
        typedName: 'Βιοχημικο Τμημα',
      );
      expect(found, isEmpty);
    });

    test('άσχετα τμήματα δεν παράγουν πρόταση', () {
      final found = SimilarDepartmentFinder.findSimilarDepartments(
        departments: [dept('ΙΤ', id: 1), dept('Χειρουργείο', id: 2)],
        typedName: 'Προσωπικού',
      );
      expect(found, isEmpty);
    });

    test('ανορθογραφία: Βιοχημκο Τμημα προτείνει Βιοχημικό Τμήμα '
        '(όταν δεν ταυτίζονται μετά κανονικοποίηση)', () {
      final existing = dept('Βιοχημικό Τμήμα', id: 1);
      final found = SimilarDepartmentFinder.findSimilarDepartments(
        departments: [existing],
        typedName: 'Βιοχημκο Τμημα',
      );
      expect(found, hasLength(1));
      expect(found.single.department.name, 'Βιοχημικό Τμήμα');
      expect(found.single.score, lessThan(100));
      expect(
        found.single.score,
        greaterThanOrEqualTo(
          SimilarDepartmentFinder.kDepartmentSuggestionMinScore,
        ),
      );
    });

    test('αποτελέσματα ταξινομημένα φθίνουσα κατά score', () {
      final departments = [
        dept('Γραφείο Προσωπικού ΑΒ', id: 1),
        dept('Προσωπικού', id: 2),
        dept('ΙΤ', id: 3),
      ];
      final found = SimilarDepartmentFinder.findSimilarDepartments(
        departments: departments,
        typedName: 'Γραφείο Προσωπικού',
      );
      expect(found, isNotEmpty);
      for (var i = 1; i < found.length; i++) {
        expect(found[i - 1].score, greaterThanOrEqualTo(found[i].score));
      }
    });

    test('παραλείπει διαγραμμένα τμήματα', () {
      final found = SimilarDepartmentFinder.findSimilarDepartments(
        departments: [dept('Γραφείο Προσωπικού', id: 1, isDeleted: true)],
        typedName: 'Προσωπικού',
      );
      expect(found, isEmpty);
    });
  });
}
