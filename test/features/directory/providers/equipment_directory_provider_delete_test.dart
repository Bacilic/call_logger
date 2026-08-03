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

        final notifier = container.read(equipmentDirectoryProvider.notifier);
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

    test(
      'με onlyIds διαγράφονται μόνο αυτά — τα υπόλοιπα μένουν επιλεγμένα',
      () async {
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        await container.read(lookupServiceProvider.future);

        final db = await DatabaseHelper.instance.database;
        final deletedId = await db.insert('equipment', {
          'code_equipment': 'PC-GOES',
          'type': 'Desktop',
          'is_deleted': 0,
        });
        final keptId = await db.insert('equipment', {
          'code_equipment': 'PC-STAYS',
          'type': 'Desktop',
          'is_deleted': 0,
        });

        final notifier = container.read(equipmentDirectoryProvider.notifier);
        await notifier.load();
        notifier.toggleSelection(deletedId);
        notifier.toggleSelection(keptId);

        await notifier
            .deleteSelected(onlyIds: {deletedId})
            .timeout(const Duration(seconds: 10));

        final rows = await db.query(
          'equipment',
          columns: ['id', 'is_deleted'],
          where: 'id IN (?, ?)',
          whereArgs: [deletedId, keptId],
        );
        final deletedById = {
          for (final r in rows) r['id'] as int: r['is_deleted'],
        };
        expect(deletedById[deletedId], 1);
        expect(deletedById[keptId], 0);

        // Το ✕ της προεπισκόπησης σημαίνει «αυτόν αργότερα», όχι «αυτόν ποτέ».
        expect(container.read(equipmentDirectoryProvider).selectedIds, {
          keptId,
        });
      },
    );
  });
}
