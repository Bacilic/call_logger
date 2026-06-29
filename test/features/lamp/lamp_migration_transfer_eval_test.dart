import 'package:call_logger/features/lamp/services/lamp_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluateField', () {
    test('unchanged όταν κανονικοποιημένες τιμές ταυτίζονται', () {
      final plan = evaluateField<DepartmentTransferField>(
        fieldKey: DepartmentTransferField.name,
        currentValue: '  Τμήμα  Α  ',
        lampValue: 'Τμήμα Α',
        destinationValue: 'τμήμα α',
      );

      expect(plan.action, TransferFieldAction.unchanged);
      expect(plan.hasWarning, isFalse);
    });

    test('linked όταν targetExists και currentValue μη-κενό', () {
      final plan = evaluateField<OwnerTransferField>(
        fieldKey: OwnerTransferField.departmentName,
        currentValue: 'Λογιστήριο',
        lampValue: 'Λογιστήριο',
        destinationValue: 'Παλιό όνομα',
        targetExists: true,
      );

      expect(plan.action, TransferFieldAction.linked);
    });

    test('created όταν destinationValue null και currentValue μη-κενό', () {
      final plan = evaluateField<EquipmentTransferField>(
        fieldKey: EquipmentTransferField.location,
        currentValue: 'Αίθουσα 3',
        lampValue: 'Αίθουσα 3',
        destinationValue: null,
      );

      expect(plan.action, TransferFieldAction.created);
    });

    test('updated όταν οι τιμές διαφέρουν ουσιαστικά', () {
      final plan = evaluateField<DepartmentTransferField>(
        fieldKey: DepartmentTransferField.building,
        currentValue: 'Κτίριο Α',
        lampValue: 'Κτίριο Α',
        destinationValue: 'Κτίριο Β',
      );

      expect(plan.action, TransferFieldAction.updated);
    });

    test('κανονικοποιημένη ισότητα αγνοεί τόνους και κεφαλαία', () {
      final plan = evaluateField<OwnerTransferField>(
        fieldKey: OwnerTransferField.firstName,
        currentValue: 'Βασίλης',
        lampValue: 'Βασίλης',
        destinationValue: 'βασιλης',
      );

      expect(plan.action, TransferFieldAction.unchanged);
    });

    test('warningCheck συμπληρώνει hasWarning ανεξάρτητα από την ενέργεια', () {
      final plan = evaluateField<OwnerTransferField>(
        fieldKey: OwnerTransferField.phones,
        currentValue: '2101234567',
        lampValue: '2101234567',
        destinationValue: '2101234567',
        warningCheck: (_, _, _) => 'Πιθανή σύγκρουση',
      );

      expect(plan.action, TransferFieldAction.unchanged);
      expect(plan.hasWarning, isTrue);
      expect(plan.warningMessage, 'Πιθανή σύγκρουση');
    });
  });

  group('evaluateItemsField', () {
    test('created για νέα στοιχεία στο currentItems', () {
      final items = evaluateItemsField<OwnerTransferField>(
        fieldKey: OwnerTransferField.phones,
        currentItems: const ['2101111111', '2102222222'],
        lampItems: const ['2101111111', '2102222222'],
        destinationItems: const ['2101111111'],
      );

      expect(items, hasLength(2));
      expect(items[0].value, '2101111111');
      expect(items[0].action, TransferFieldAction.unchanged);
      expect(items[1].value, '2102222222');
      expect(items[1].action, TransferFieldAction.created);
    });

    test('unlinked για στοιχεία μόνο στο destinationItems', () {
      final items = evaluateItemsField<OwnerTransferField>(
        fieldKey: OwnerTransferField.equipmentCodes,
        currentItems: const ['PC-01'],
        lampItems: const ['PC-01'],
        destinationItems: const ['PC-01', 'PC-02'],
      );

      final unlinked = items.where((i) => i.action == TransferFieldAction.unlinked);
      expect(unlinked, hasLength(1));
      expect(unlinked.first.value, 'PC-02');
      expect(unlinked.first.warningMessage, 'Θα αποσυνδεθεί');
      expect(unlinked.first.hasWarning, isTrue);
    });

    test('κανονικοποιημένη σύγκριση στοιχείων', () {
      final items = evaluateItemsField<OwnerTransferField>(
        fieldKey: OwnerTransferField.phones,
        currentItems: const [' 2103333333 '],
        lampItems: const ['2103333333'],
        destinationItems: const ['2103333333'],
      );

      expect(items, hasLength(1));
      expect(items.first.action, TransferFieldAction.unchanged);
    });

    test('conflictCheck καλείται ανά στοιχείο', () {
      final warned = <String>[];
      evaluateItemsField<OwnerTransferField>(
        fieldKey: OwnerTransferField.phones,
        currentItems: const ['2104444444'],
        lampItems: const ['2104444444'],
        destinationItems: const [],
        conflictCheck: (item, action) {
          warned.add('$item:${action.name}');
          return null;
        },
      );

      expect(warned, ['2104444444:created']);
    });
  });

  group('parseEquipmentCodes', () {
    test('αφαιρεί διπλότυπα με κανονικοποιημένη σύγκριση', () {
      expect(
        LampMigrationService.parseEquipmentCodes('PC-01, pc-01; PC-02'),
        ['PC-01', 'PC-02'],
      );
    });
  });
}
