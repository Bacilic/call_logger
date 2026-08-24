// Ο φρουρός μπαγιάτικης εγγραφής: σε κοινόχρηστη βάση δύο χρήστες κρατούν ο
// καθένας τη δική του εικόνα, και ο δεύτερος που αποθηκεύει δεν επιτρέπεται να
// σβήσει σιωπηλά τη δουλειά του πρώτου.
//
//   flutter test test/core/database/tasks_repository_stale_write_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/core/errors/task_stale_exception.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('TasksRepository — φρουρός μπαγιάτικης εγγραφής', () {
    late TasksRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('tasks_stale_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/tasks_stale.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('tasks');
      repo = TasksRepository();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<Task> readTask(int id) async {
      final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
      return Task.fromMap(Map<String, dynamic>.from(rows.single));
    }

    /// Στήνει το σενάριο: ο Bacilic κρατά την εικόνα των 16:31, ο Βλάσης
    /// ολοκληρώνει στο μεταξύ.
    Future<({Task stale, int id})> staleAfterOtherClosed() async {
      final id = await repo.createTask(
        Task(
          title: 'Για δω τι θα δω;',
          description: 'Δοκιμή για χρήστες',
          dueDate: DateTime(2026, 8, 22, 16, 31).toIso8601String(),
          status: 'open',
        ),
      );
      // Η εικόνα που κρατά η οθόνη του Bacilic.
      final stale = await readTask(id);

      // Ο Βλάσης ολοκληρώνει από το δικό του μηχάνημα.
      await repo.closeTask(id, 'Αντικαταστάθηκε το καλώδιο.');

      final afterOther = await readTask(id);
      expect(
        afterOther.updatedAt,
        isNot(stale.updatedAt),
        reason:
            'Χωρίς αλλαγή σφραγίδας το σενάριο δεν στήθηκε — το τεστ θα ήταν κενό',
      );
      return (stale: stale, id: id);
    }

    test('updateTask: η ξένη ολοκλήρωση δεν εξαφανίζεται σιωπηλά', () async {
      final scenario = await staleAfterOtherClosed();

      await expectLater(
        () => repo.updateTask(
          scenario.stale.copyWith(status: TaskStatus.snoozed.toDbValue),
        ),
        throwsA(isA<TaskStaleException>()),
      );

      final row = await readTask(scenario.id);
      expect(
        row.status,
        TaskStatus.closed.toDbValue,
        reason: 'Η ολοκλήρωση του άλλου χρήστη πρέπει να έχει μείνει ακέραιη',
      );
      expect(row.solutionNotes, 'Αντικαταστάθηκε το καλώδιο.');
    });

    test('updateTask: η εξαίρεση δείχνει τη φρέσκια εγγραφή', () async {
      final scenario = await staleAfterOtherClosed();

      try {
        await repo.updateTask(
          scenario.stale.copyWith(status: TaskStatus.open.toDbValue),
        );
        fail('Έπρεπε να απορριφθεί η μπαγιάτικη εγγραφή');
      } on TaskStaleException catch (e) {
        expect(e.fresh.status, TaskStatus.closed.toDbValue);
        expect(e.fresh.solutionNotes, 'Αντικαταστάθηκε το καλώδιο.');
        expect(e.attempted.status, TaskStatus.open.toDbValue);
        expect(
          e.changedAt,
          isNotNull,
          reason: 'Η στιγμή της ξένης αλλαγής έρχεται από το Ιστορικό',
        );
      }
    });

    test('updateTask: με force ο χρήστης γράφει εν γνώσει του', () async {
      final scenario = await staleAfterOtherClosed();

      await repo.updateTask(
        scenario.stale.copyWith(status: TaskStatus.open.toDbValue),
        force: true,
      );

      final row = await readTask(scenario.id);
      expect(row.status, TaskStatus.open.toDbValue);
    });

    test('updateTask: χωρίς διένεξη γράφει κανονικά', () async {
      final id = await repo.createTask(
        Task(
          title: 'Ήσυχη εκκρεμότητα',
          dueDate: DateTime(2026, 8, 22, 16, 31).toIso8601String(),
          status: 'open',
        ),
      );
      final fresh = await readTask(id);

      await repo.updateTask(fresh.copyWith(title: 'Μετονομασμένη'));

      expect((await readTask(id)).title, 'Μετονομασμένη');
    });

    test('closeTask: δεύτερο κλείσιμο δεν σβήνει την ξένη λύση', () async {
      final scenario = await staleAfterOtherClosed();

      await expectLater(
        () => repo.closeTask(
          scenario.id,
          'Άν την έχει ολοκληρώσει ο Βλάσης;;',
          expectedUpdatedAt: scenario.stale.updatedAt,
        ),
        throwsA(isA<TaskStaleException>()),
      );

      expect(
        (await readTask(scenario.id)).solutionNotes,
        'Αντικαταστάθηκε το καλώδιο.',
      );
    });

    test('closeTask: με force γράφεται η δική μου λύση', () async {
      final scenario = await staleAfterOtherClosed();

      await repo.closeTask(
        scenario.id,
        'Άν την έχει ολοκληρώσει ο Βλάσης;;',
        expectedUpdatedAt: scenario.stale.updatedAt,
        force: true,
      );

      expect(
        (await readTask(scenario.id)).solutionNotes,
        'Άν την έχει ολοκληρώσει ο Βλάσης;;',
      );
    });

    test('closeTask: χωρίς αναμενόμενη σφραγίδα δεν μπλοκάρει', () async {
      // Fail-open: ροή ή εγγραφή που δεν κουβαλά αφετηρία δεν γίνεται άσωστη.
      final scenario = await staleAfterOtherClosed();

      await repo.closeTask(scenario.id, 'Χωρίς σφραγίδα.');

      expect((await readTask(scenario.id)).solutionNotes, 'Χωρίς σφραγίδα.');
    });
  });
}
