import 'package:call_logger/features/directory/services/department_deletion_undo_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveDepartmentDeletionUndo', () {
    test('μηδενικές μετακινήσεις → canOfferUndo true και κανονικό μήνυμα', () {
      final one = resolveDepartmentDeletionUndo(
        deletedDepartmentCount: 1,
        movedEmployeeCount: 0,
        movedOrDeletedAssetCount: 0,
      );
      expect(one.canOfferUndo, isTrue);
      expect(one.snackbarMessage, 'Σημειώθηκαν ως διαγραμμένα 1 τμήμα.');

      final many = resolveDepartmentDeletionUndo(
        deletedDepartmentCount: 3,
        movedEmployeeCount: 0,
        movedOrDeletedAssetCount: 0,
      );
      expect(many.canOfferUndo, isTrue);
      expect(many.snackbarMessage, 'Σημειώθηκαν ως διαγραμμένα 3 τμήματα.');
    });

    test(
      'μετακίνηση υπαλλήλων → canOfferUndo true και μήνυμα πλήρους αναίρεσης',
      () {
        final result = resolveDepartmentDeletionUndo(
          deletedDepartmentCount: 1,
          movedEmployeeCount: 2,
          movedOrDeletedAssetCount: 0,
        );
        expect(result.canOfferUndo, isTrue);
        expect(
          result.snackbarMessage,
          contains('Επαναφέρθηκαν και τα μετακινημένα στοιχεία'),
        );
      },
    );

    test(
      'μετακίνηση/διαγραφή κοινόχρηστων χωρίς υπαλλήλους → canOfferUndo true',
      () {
        final result = resolveDepartmentDeletionUndo(
          deletedDepartmentCount: 2,
          movedEmployeeCount: 0,
          movedOrDeletedAssetCount: 4,
        );
        expect(result.canOfferUndo, isTrue);
        expect(
          result.snackbarMessage,
          contains('Επαναφέρθηκαν και τα μετακινημένα στοιχεία'),
        );
      },
    );
  });
}
