// Η μνήμη της εκκρεμότητας για το Lansweeper: τι γράφεται, τι ΔΕΝ γράφεται,
// και ότι η αποθήκευση της φόρμας δεν αγγίζει ποτέ αυτές τις τρεις στήλες.
//
//   flutter test test/core/database/tasks_lansweeper_repository_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_lansweeper_repository.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('TasksLansweeperRepository', () {
    late TasksLansweeperRepository repo;
    late TasksRepository tasksRepo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'tasks_lansweeper_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/tasks_ls.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('tasks');
      await db.delete('calls');
      repo = TasksLansweeperRepository(db);
      tasksRepo = TasksRepository();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    // Η στήλη `call_id` έχει ξένο κλειδί προς `calls`: εκκρεμότητα που δείχνει
    // σε ανύπαρκτη κλήση απορρίπτεται από τη βάση, οπότε η κλήση γεννιέται
    // πρώτη.
    Future<int> newCall({String issue = 'Δεν τυπώνει'}) =>
        db.insert('calls', {'issue': issue});

    Future<int> newTask({int? callId, String title = 'Δεν τυπώνει'}) {
      return tasksRepo.createTask(
        Task(
          callId: callId,
          title: title,
          dueDate: DateTime.now().toIso8601String(),
          status: 'open',
        ),
      );
    }

    test('νέα εκκρεμότητα ξεκινά ακαταχώρητη και χωρίς αίτημα', () async {
      final id = await newTask();

      final snapshot = await repo.readState(id);

      expect(snapshot, isNotNull);
      expect(snapshot!.state, TasksLansweeperRepository.stateUnsent);
      expect(snapshot.ticketId, isEmpty);
      expect(snapshot.hasTicket, isFalse);
      expect(snapshot.lastSyncAt, isNull);
    });

    test('η αποστολή κρατά τον αριθμό, την κατάσταση και την ώρα', () async {
      final id = await newTask();

      final changed = await repo.markSubmitted(taskId: id, ticketId: '4821');

      expect(changed, isTrue);
      final snapshot = await repo.readState(id);
      expect(snapshot!.state, TasksLansweeperRepository.stateSent);
      expect(snapshot.ticketId, '4821');
      expect(snapshot.hasTicket, isTrue);
      expect(snapshot.lastSyncAt, isNotNull);
    });

    test('η ίδια αποστολή δεύτερη φορά δεν γράφει ξανά στο Ιστορικό', () async {
      final id = await newTask();
      await repo.markSubmitted(taskId: id, ticketId: '4821');
      final firstCount = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM audit_log',
      )).first['c'];

      final changed = await repo.markSubmitted(taskId: id, ticketId: '4821');

      expect(changed, isFalse);
      final secondCount = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM audit_log',
      )).first['c'];
      expect(secondCount, firstCount);
    });

    test('η αποτυχία ΔΕΝ σβήνει αίτημα που είχε ήδη γεννηθεί', () async {
      final id = await newTask();
      await repo.markSubmitted(taskId: id, ticketId: '4821');

      await repo.markFailed(taskId: id);

      final snapshot = await repo.readState(id);
      expect(snapshot!.state, TasksLansweeperRepository.stateFailed);
      expect(
        snapshot.ticketId,
        '4821',
        reason:
            'χωρίς τον αριθμό, το αίτημα μένει ορφανό στο Lansweeper και '
            'κανείς δεν μπορεί να το βρει',
      );
    });

    test(
      'η αποθήκευση της φόρμας ΔΕΝ αγγίζει την κατάσταση Lansweeper',
      () async {
        final id = await newTask();
        await repo.markSubmitted(taskId: id, ticketId: '4821');

        // Ό,τι κάνει η φόρμα επεξεργασίας: διαβάζει, αλλάζει κείμενο, γράφει
        // ολόκληρη την καρτέλα πίσω.
        final loaded = Task.fromMap(
          (await db.query('tasks', where: 'id = ?', whereArgs: [id])).first,
        );
        await tasksRepo.updateTask(loaded.copyWith(title: 'Νέος τίτλος'));

        final snapshot = await repo.readState(id);
        expect(snapshot!.state, TasksLansweeperRepository.stateSent);
        expect(snapshot.ticketId, '4821');
      },
    );

    test('η αποστολή ΔΕΝ αγγίζει το κείμενο της εκκρεμότητας', () async {
      final id = await tasksRepo.createTask(
        Task(
          title: 'Ο τίτλος του ανθρώπου',
          description: 'Η προσεγμένη περιγραφή.',
          solutionNotes: 'Η λύση όπως τη γράψαμε.',
          dueDate: DateTime.now().toIso8601String(),
          status: 'open',
        ),
      );

      await repo.markSubmitted(taskId: id, ticketId: '4821');

      final after = Task.fromMap(
        (await db.query('tasks', where: 'id = ?', whereArgs: [id])).first,
      );
      expect(after.title, 'Ο τίτλος του ανθρώπου');
      expect(after.description, 'Η προσεγμένη περιγραφή.');
      expect(
        after.solutionNotes,
        'Η λύση όπως τη γράψαμε.',
        reason:
            'το κείμενο της εκκρεμότητας είναι γραμμένο από άνθρωπο και δεν '
            'αντικαθίσταται από ό,τι διατύπωσε η ΤΝ για το helpdesk',
      );
    });

    group('η ρητή αποθήκευση κειμένου', () {
      test('γράφει και τα τρία πεδία στη θέση τους', () async {
        final id = await newTask();

        final saved = await repo.saveTexts(
          taskId: id,
          title: 'Καθαρός τίτλος',
          problem: 'Καθαρή περιγραφή.',
          solution: 'Καθαρή λύση.',
        );

        expect(saved, isTrue);
        final after = Task.fromMap(
          (await db.query('tasks', where: 'id = ?', whereArgs: [id])).first,
        );
        expect(after.title, 'Καθαρός τίτλος');
        expect(after.description, 'Καθαρή περιγραφή.');
        expect(after.solutionNotes, 'Καθαρή λύση.');
      });

      test('κενό πεδίο αφήνει ό,τι υπάρχει', () async {
        final id = await tasksRepo.createTask(
          Task(
            title: 'Παλιός τίτλος',
            description: 'Παλιά περιγραφή.',
            dueDate: DateTime.now().toIso8601String(),
            status: 'open',
          ),
        );

        await repo.saveTexts(
          taskId: id,
          title: '',
          problem: 'Νέα περιγραφή.',
          solution: '',
        );

        final after = Task.fromMap(
          (await db.query('tasks', where: 'id = ?', whereArgs: [id])).first,
        );
        expect(after.title, 'Παλιός τίτλος');
        expect(after.description, 'Νέα περιγραφή.');
      });

      test('χωρίς καμία αλλαγή δεν γράφει ούτε στο Ιστορικό', () async {
        final id = await newTask(title: 'Ίδιος τίτλος');
        await db.delete('audit_log');

        final saved = await repo.saveTexts(
          taskId: id,
          title: 'Ίδιος τίτλος',
          problem: '',
          solution: '',
        );

        expect(saved, isFalse);
        final logged = (await db.rawQuery(
          'SELECT COUNT(*) AS c FROM audit_log',
        )).first['c'];
        expect(logged, 0);
      });

      test('η αποθήκευση ΔΕΝ αγγίζει την κατάσταση Lansweeper', () async {
        final id = await newTask();
        await repo.markSubmitted(taskId: id, ticketId: '4821');

        await repo.saveTexts(
          taskId: id,
          title: 'Άλλος τίτλος',
          problem: 'Άλλη περιγραφή.',
          solution: '',
        );

        final snapshot = await repo.readState(id);
        expect(snapshot!.state, TasksLansweeperRepository.stateSent);
        expect(snapshot.ticketId, '4821');
      });
    });

    test('το μοντέλο διαβάζει τις τρεις στήλες από τη βάση', () async {
      final id = await newTask();
      await repo.markSubmitted(taskId: id, ticketId: '4821');

      final loaded = Task.fromMap(
        (await db.query('tasks', where: 'id = ?', whereArgs: [id])).first,
      );

      expect(loaded.lansweeperState, TasksLansweeperRepository.stateSent);
      expect(loaded.lansweeperMainTicketId, '4821');
      expect(loaded.lansweeperLastSyncAt, isNotNull);
    });

    group('οι εκκρεμότητες μιας κλήσης που έχουν ήδη αίτημα', () {
      test('δείχνει μόνο όσες έχουν αριθμό', () async {
        final callId = await newCall();
        final withTicket = await newTask(callId: callId, title: 'Με αίτημα');
        await newTask(callId: callId, title: 'Χωρίς αίτημα');
        await repo.markSubmitted(taskId: withTicket, ticketId: '4821');

        final found = await repo.ticketedTasksForCall(callId);

        expect(found, hasLength(1));
        expect(found.single.taskId, withTicket);
        expect(found.single.ticketId, '4821');
      });

      test('οι διαγραμμένες μένουν έξω', () async {
        final callId = await newCall();
        final id = await newTask(callId: callId);
        await repo.markSubmitted(taskId: id, ticketId: '4821');
        await tasksRepo.deleteTask(id);

        expect(await repo.ticketedTasksForCall(callId), isEmpty);
      });

      test('εκκρεμότητα άλλης κλήσης δεν μπερδεύεται', () async {
        final mine = await newCall(issue: 'η δική μου');
        final other = await newCall(issue: 'άλλη κλήση');
        final id = await newTask(callId: other);
        await repo.markSubmitted(taskId: id, ticketId: '4821');

        expect(await repo.ticketedTasksForCall(mine), isEmpty);
      });
    });
  });
}
