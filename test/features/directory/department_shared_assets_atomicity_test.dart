// Ατομικότητα σύνθετης επεξεργασίας κοινόχρηστων στοιχείων τμήματος.
//
// Συμβόλαιο: κάθε σύνθετη μετάβαση δεδομένων εκτελείται σε ΜΙΑ συναλλαγή —
// διακοπή/σφάλμα στη μέση δεν αφήνει μισοτελειωμένη κατάσταση.
//
//   flutter test test/features/directory/department_shared_assets_atomicity_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/phone_repository.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('updateDepartmentSharedAssets — ατομικότητα', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
    });

    test('σφάλμα ελέγχου στη μέση αναιρεί και τις ήδη γραμμένες '
        'αλλαγές τηλεφώνων (μία συναλλαγή, όχι μισοτελειωμένη κατάσταση)',
        () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      await container.read(lookupServiceProvider.future);

      final db = await DatabaseHelper.instance.database;
      final deptRows = await db.query(
        'departments',
        where: 'name = ? AND COALESCE(is_deleted, 0) = 0',
        whereArgs: [kTestDepartmentName],
        limit: 1,
      );
      expect(deptRows, isNotEmpty);
      final deptId = deptRows.first['id'] as int;

      // Κοινόχρηστο τηλέφωνο τμήματος + κοινόχρηστος εξοπλισμός χωρίς κάτοχο.
      const directPhone = '2109998877';
      await PhoneRepository(db).addDepartmentDirectPhone(deptId, directPhone);
      await db.insert('equipment', {
        'code_equipment': 'EQ-ΑΤΟΜΙΚΟ',
        'type': 'Desktop',
        'department_id': deptId,
        'is_deleted': 0,
      });
      await LookupService.instance.loadFromDatabase(forceRefresh: true);

      final notifier = container.read(departmentDirectoryProvider.notifier);

      // Αφαίρεση ΚΑΙ του τηλεφώνου ΚΑΙ του εξοπλισμού· ο εξοπλισμός δεν έχει
      // ούτε κάτοχο ούτε διάθεση (μεταφορά/διαγραφή) → ο έλεγχος σκάει ΑΦΟΥ
      // έχει προηγηθεί η αφαίρεση του τηλεφώνου.
      await expectLater(
        notifier.updateDepartmentSharedAssets(
          deptId,
          sharedPhones: const [],
          sharedEquipmentCodes: const [],
        ),
        throwsA(isA<StateError>()),
      );

      final phoneRows = await db.rawQuery(
        '''
        SELECT dp.phone_id
        FROM department_phones dp
        JOIN phones p ON p.id = dp.phone_id
        WHERE dp.department_id = ? AND p.number = ?
        ''',
        [deptId, directPhone],
      );
      expect(
        phoneRows,
        isNotEmpty,
        reason:
            'η αφαίρεση τηλεφώνου πρέπει να αναιρείται όταν αποτύχει '
            'επόμενο βήμα της ίδιας αποθήκευσης',
      );
    });
  });
}
