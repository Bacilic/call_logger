import 'package:call_logger/features/directory/services/department_rename_heuristic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('looksLikeDepartmentRename', () {
    test('νέο τμήμα με 100% → true', () {
      expect(
        looksLikeDepartmentRename(
          movedTotal: 10,
          movedToDominantTarget: 10,
          dominantTargetIsNew: true,
        ),
        isTrue,
      );
    });

    test('νέο τμήμα με 50% → true', () {
      expect(
        looksLikeDepartmentRename(
          movedTotal: 10,
          movedToDominantTarget: 5,
          dominantTargetIsNew: true,
        ),
        isTrue,
      );
    });

    test('νέο τμήμα με 30% → false', () {
      expect(
        looksLikeDepartmentRename(
          movedTotal: 10,
          movedToDominantTarget: 3,
          dominantTargetIsNew: true,
        ),
        isFalse,
      );
    });

    test('υπάρχον τμήμα ακόμη και με 100% → false', () {
      expect(
        looksLikeDepartmentRename(
          movedTotal: 10,
          movedToDominantTarget: 10,
          dominantTargetIsNew: false,
        ),
        isFalse,
      );
    });

    test('movedTotal=0 → false', () {
      expect(
        looksLikeDepartmentRename(
          movedTotal: 0,
          movedToDominantTarget: 0,
          dominantTargetIsNew: true,
        ),
        isFalse,
      );
    });
  });
}
