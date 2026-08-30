// Η μαζική παλέτα βάφει πολλά τμήματα μονομιάς. Περνούσε από την καρτέλα, οπότε
// ξανάγραφε όνομα, κτίριο και σημειώσεις από μια λίστα που μπορεί να έχει
// γεράσει — η αλλαγή του συναδέλφου εξαφανιζόταν σιωπηλά.
//
//   flutter test test/features/directory/department_palette_bulk_color_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Μαζική παλέτα τμημάτων — γράφει μόνο το χρώμα', () {
    Future<ProviderContainer> openScreen() async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      await container.read(lookupServiceProvider.future);
      await container
          .read(departmentDirectoryProvider.notifier)
          .loadDepartments();
      return container;
    }

    Future<int> seedDepartment(String name) async {
      final db = await DatabaseHelper.instance.database;
      final id = await DepartmentRepository(
        db,
      ).getOrCreateDepartmentIdByName(name);
      return id!;
    }

    Future<Map<String, Object?>> departmentRow(int id) async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'departments',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return Map<String, Object?>.from(rows.first);
    }

    test(
      'το κτίριο που έγραψε ο συνάδελφος επιβιώνει της μαζικής βαφής',
      () async {
        final id = await seedDepartment('ΤΕΠ');
        final container = await openScreen();
        final notifier = container.read(departmentDirectoryProvider.notifier);

        // Η οθόνη μου κρατά την εικόνα ΠΡΙΝ την αλλαγή του συναδέλφου.
        final stale = DepartmentModel(id: id, name: 'ΤΕΠ');

        final db = await DatabaseHelper.instance.database;
        await DepartmentRepository(db).updateDepartment(id, {
          'building': 'Νέα Πτέρυγα',
          'notes': 'Μεταφέρθηκε στον 3ο',
        }, expected: null);

        await notifier.setDepartmentsColor(<DepartmentModel>[stale], '#FF0000');

        final row = await departmentRow(id);
        expect(row['color'], '#FF0000', reason: 'το χρώμα γράφτηκε');
        expect(
          row['building'],
          'Νέα Πτέρυγα',
          reason: 'το κτίριο του συναδέλφου δεν επιτρέπεται να σβηστεί',
        );
        expect(row['notes'], 'Μεταφέρθηκε στον 3ο');
      },
    );

    test('βάφει όλα τα τμήματα της επιλογής', () async {
      final first = await seedDepartment('ΤΕΠ');
      final second = await seedDepartment('Γραμματεία');
      final container = await openScreen();
      final notifier = container.read(departmentDirectoryProvider.notifier);

      await notifier.setDepartmentsColor(<DepartmentModel>[
        DepartmentModel(id: first, name: 'ΤΕΠ'),
        DepartmentModel(id: second, name: 'Γραμματεία'),
      ], '#00FF00');

      expect((await departmentRow(first))['color'], '#00FF00');
      expect((await departmentRow(second))['color'], '#00FF00');
    });

    test(
      'το όνομα δεν κρίνεται καν — διπλότυπο δεν μπλοκάρει τη βαφή',
      () async {
        final id = await seedDepartment('ΤΕΠ');
        final container = await openScreen();
        final notifier = container.read(departmentDirectoryProvider.notifier);

        // Άλλο τμήμα με το ίδιο όνομα δεν μπορεί να υπάρξει· η μπαγιάτικη εικόνα
        // όμως μπορεί να κουβαλά όνομα που στο μεταξύ πήρε άλλος. Η βαφή δεν
        // αγγίζει όνομα, άρα δεν έχει λόγο να σταματήσει.
        final stale = DepartmentModel(id: id, name: 'Γραμματεία');
        await seedDepartment('Γραμματεία');

        await notifier.setDepartmentsColor(<DepartmentModel>[stale], '#0000FF');

        final row = await departmentRow(id);
        expect(row['color'], '#0000FF');
        expect(row['name'], 'ΤΕΠ', reason: 'το όνομα έμεινε ανέπαφο');
      },
    );
  });
}
