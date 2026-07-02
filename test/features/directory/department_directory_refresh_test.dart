// Έλεγχος: departmentDirectoryProvider mutations ανανεώνουν sibling καταλόγους.
//
//   flutter test test/features/directory/department_directory_refresh_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../test_setup.dart';

Future<ProviderContainer> _container() async {
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  await container.read(lookupServiceProvider.future);
  return container;
}

Future<void> _preloadSiblingCatalogs(ProviderContainer container) async {
  await container.read(directoryProvider.notifier).loadUsers();
  await container.read(equipmentDirectoryProvider.notifier).load();
  await container.read(departmentDirectoryProvider.notifier).loadDepartments();
}

Future<int> _seedDepartmentId() async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'departments',
    where: 'name = ? AND COALESCE(is_deleted, 0) = 0',
    whereArgs: [kTestDepartmentName],
    limit: 1,
  );
  expect(rows, isNotEmpty);
  return rows.first['id'] as int;
}

Future<void> _insertOrphanPhone(String number, int departmentId) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('phones', {
    'number': number,
    'department_id': departmentId,
    'is_deleted': 0,
  });
}

String? _orphanPhoneDeptLabel(ProviderContainer container, String number) {
  for (final entry in container.read(directoryProvider).allNonUserPhones) {
    if (entry.number.contains(number)) {
      return entry.departmentNamesDisplay;
    }
  }
  return null;
}

Future<void> _selectDepartment(
  ProviderContainer container,
  int departmentId,
) async {
  final notifier = container.read(departmentDirectoryProvider.notifier);
  notifier.toggleSelection(departmentId);
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('DepartmentDirectoryNotifier — sibling catalog refresh', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
    });

    test('bulkUpdate — ενημέρωση ονόματος τμήματος σε κοινόχρηστο τηλέφωνο', () async {
      final container = await _container();
      final deptId = await _seedDepartmentId();
      const orphanPhone = '5551';
      const renamedDept = 'Τμήμα Μετονομασμένο';

      await _insertOrphanPhone(orphanPhone, deptId);
      await _preloadSiblingCatalogs(container);

      expect(
        _orphanPhoneDeptLabel(container, orphanPhone),
        contains(kTestDepartmentName),
      );

      await container.read(departmentDirectoryProvider.notifier).bulkUpdate(
            [deptId],
            {
              'name': renamedDept,
              'name_key': SearchTextNormalizer.normalizeForSearch(renamedDept),
            },
          );

      expect(
        _orphanPhoneDeptLabel(container, orphanPhone),
        contains(renamedDept),
        reason:
            'Μετά bulkUpdate το directoryProvider πρέπει να δείχνει το νέο όνομα τμήματος χωρίς loadUsers()',
      );

      container.dispose();
    });

    test('deleteSelected — αφαίρεση ονόματος τμήματος από κοινόχρηστο τηλέφωνο', () async {
      final container = await _container();
      final deptId = await _seedDepartmentId();
      const orphanPhone = '5552';

      await _insertOrphanPhone(orphanPhone, deptId);
      await _preloadSiblingCatalogs(container);

      expect(
        _orphanPhoneDeptLabel(container, orphanPhone),
        contains(kTestDepartmentName),
      );

      await _selectDepartment(container, deptId);
      await container.read(departmentDirectoryProvider.notifier).deleteSelected();

      final label = _orphanPhoneDeptLabel(container, orphanPhone);
      expect(
        label == null || !label.contains(kTestDepartmentName),
        isTrue,
        reason:
            'Μετά deleteSelected το κοινόχρηστο τηλέφωνο δεν πρέπει να δείχνει soft-deleted τμήμα (χωρίς loadUsers())',
      );

      container.dispose();
    });

    test('undoLastDelete — επαναφορά ονόματος τμήματος σε κοινόχρηστο τηλέφωνο', () async {
      final container = await _container();
      final deptId = await _seedDepartmentId();
      const orphanPhone = '5553';

      await _insertOrphanPhone(orphanPhone, deptId);
      await _preloadSiblingCatalogs(container);

      await _selectDepartment(container, deptId);
      await container.read(departmentDirectoryProvider.notifier).deleteSelected();
      expect(
        _orphanPhoneDeptLabel(container, orphanPhone) == null ||
            !_orphanPhoneDeptLabel(container, orphanPhone)!
                .contains(kTestDepartmentName),
        isTrue,
      );

      await container.read(departmentDirectoryProvider.notifier).undoLastDelete();

      expect(
        _orphanPhoneDeptLabel(container, orphanPhone),
        contains(kTestDepartmentName),
        reason:
            'Μετά undoLastDelete το directoryProvider πρέπει να επαναφέρει το όνομα τμήματος χωρίς loadUsers()',
      );

      container.dispose();
    });

    test('undoLastBulkUpdate — επαναφορά παλιού ονόματος τμήματος', () async {
      final container = await _container();
      final deptId = await _seedDepartmentId();
      const orphanPhone = '5554';
      const renamedDept = 'Τμήμα Προσωρινό';

      await _insertOrphanPhone(orphanPhone, deptId);
      await _preloadSiblingCatalogs(container);

      await container.read(departmentDirectoryProvider.notifier).bulkUpdate(
            [deptId],
            {
              'name': renamedDept,
              'name_key': SearchTextNormalizer.normalizeForSearch(renamedDept),
            },
          );
      expect(
        _orphanPhoneDeptLabel(container, orphanPhone),
        contains(renamedDept),
      );

      await container
          .read(departmentDirectoryProvider.notifier)
          .undoLastBulkUpdate();

      expect(
        _orphanPhoneDeptLabel(container, orphanPhone),
        contains(kTestDepartmentName),
        reason:
            'Μετά undoLastBulkUpdate το directoryProvider πρέπει να επαναφέρει το αρχικό όνομα χωρίς loadUsers()',
      );

      container.dispose();
    });

    test('restoreDepartmentByName — επαναφορά soft-deleted τμήματος στον κατάλογο τηλεφώνων', () async {
      final container = await _container();
      final deptId = await _seedDepartmentId();
      const orphanPhone = '5555';

      await _insertOrphanPhone(orphanPhone, deptId);
      await _preloadSiblingCatalogs(container);

      final db = await DatabaseHelper.instance.database;
      await db.update(
        'departments',
        {'is_deleted': 1},
        where: 'id = ?',
        whereArgs: [deptId],
      );

      await container.read(lookupServiceProvider.future);
      await container.read(directoryProvider.notifier).loadUsers();
      final labelAfterSoftDelete = _orphanPhoneDeptLabel(container, orphanPhone);
      expect(
        labelAfterSoftDelete == null ||
            !labelAfterSoftDelete.contains(kTestDepartmentName),
        isTrue,
      );

      await container
          .read(departmentDirectoryProvider.notifier)
          .restoreDepartmentByName(kTestDepartmentName);

      expect(
        _orphanPhoneDeptLabel(container, orphanPhone),
        contains(kTestDepartmentName),
        reason:
            'Μετά restoreDepartmentByName το directoryProvider πρέπει να δείχνει το τμήμα χωρίς επιπλέον loadUsers()',
      );

      container.dispose();
    });

    // addDepartment: νέο κενό τμήμα — δεν αλλάζει cached sibling λίστες
    // (χρήστες/εξοπλισμός/κοινόχρηστα) με τρόπο ελέγξιμο χωρίς mocks.
    // Μη ελέγξιμο σήμερα σε επίπεδο provider τεστ.
  });
}
