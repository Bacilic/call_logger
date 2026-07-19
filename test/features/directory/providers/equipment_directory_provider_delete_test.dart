// Αναπαραγωγή / κλείδωμα: deleteSelected εξοπλισμού δεν κάνει deadlock με εξωτερικό transaction.
//
//   flutter test test/features/directory/providers/equipment_directory_provider_delete_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('EquipmentDirectoryNotifier.deleteSelected — χωρίς deadlock', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
    });

    test(
      'deleteSelected ολοκληρώνεται εντός ορίου και θέτει is_deleted = 1',
      () async {
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        await container.read(lookupServiceProvider.future);

        final db = await DatabaseHelper.instance.database;
        final eqId = await db.insert('equipment', {
          'code_equipment': 'PC-DELETE-DEADLOCK',
          'type': 'Desktop',
          'is_deleted': 0,
        });

        final notifier =
            container.read(equipmentDirectoryProvider.notifier);
        await notifier.load();
        notifier.toggleSelection(eqId);

        expect(
          container.read(equipmentDirectoryProvider).selectedIds,
          contains(eqId),
        );

        await notifier.deleteSelected().timeout(const Duration(seconds: 10));

        final rows = await db.query(
          'equipment',
          where: 'id = ?',
          whereArgs: [eqId],
          limit: 1,
        );
        expect(rows, hasLength(1));
        expect(rows.single['is_deleted'], 1);
      },
    );
  });
}
