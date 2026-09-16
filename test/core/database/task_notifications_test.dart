// Ποιος μαθαίνει τι, όταν κάποιος αγγίζει ξένη εκκρεμότητα.
//
// Και οι τέσσερις πύλες αφήνουν ειδοποίηση: η γρήγορη ανάθεση του μενού, η
// φόρμα επεξεργασίας, η δημιουργία με ανάθεση εξαρχής, και ο διάλογος
// ολοκλήρωσης. Η ανάθεση και η αφαίρεσή της είναι η ίδια πράξη με αντίθετη
// φορά — σε μεταβίβαση ειδοποιούνται και οι δύο άνθρωποι.
//
// Κανείς δεν ειδοποιεί ποτέ τον εαυτό του.
//
//   flutter test test/core/database/task_notifications_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/task_notifications_repository.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/models/task_notification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Ο Βασίλης δουλεύει· ο Βλάσης είναι ο συνάδελφος της άλλης βάρδιας.
const int kVasilis = 11;
const int kVlasis = 22;
const int kMaria = 33;

void main() {
  group('Ειδοποιήσεις εκκρεμοτήτων', () {
    late TasksRepository repo;
    late TaskNotificationsRepository notifications;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'task_notifications_test_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/notifications.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('task_notifications');
      await db.delete('tasks');
      repo = TasksRepository();
      notifications = TaskNotificationsRepository();
      CurrentOperator.activate(_person(kVasilis, 'Βασίλης'));
    });

    tearDown(CurrentOperator.reset);

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Task newTask({int? assignedTo}) => Task(
      title: 'Δεν τυπώνει ο εκτυπωτής του ΤΕΠ',
      dueDate: DateTime(2026, 9, 1, 9).toIso8601String(),
      status: 'open',
      assignedOperatorId: assignedTo,
    );

    Future<List<TaskNotification>> inboxOf(int operatorId) =>
        notifications.unseenFor(operatorId);

    Future<Task> taskOf(int id) async => Task.fromMap(
      (await db.query('tasks', where: 'id = ?', whereArgs: [id])).single,
    );

    group('ανάθεση από το μενού της κάρτας', () {
      test('ο παραλήπτης μαθαίνει ότι του ανατέθηκε', () async {
        final id = await repo.createTask(newTask());

        await repo.assignTask(id, kVlasis);

        final inbox = await inboxOf(kVlasis);
        expect(inbox, hasLength(1));
        expect(inbox.single.kind, TaskNotificationKind.assigned);
        expect(inbox.single.taskId, id);
        expect(inbox.single.actorOperatorId, kVasilis);
        expect(inbox.single.taskTitle, 'Δεν τυπώνει ο εκτυπωτής του ΤΕΠ');
      });

      test('μεταβίβαση: μαθαίνουν και οι δύο', () async {
        final id = await repo.createTask(newTask(assignedTo: kVlasis));
        await db.delete('task_notifications');

        await repo.assignTask(id, kMaria);

        expect(
          (await inboxOf(kMaria)).single.kind,
          TaskNotificationKind.assigned,
        );
        expect(
          (await inboxOf(kVlasis)).single.kind,
          TaskNotificationKind.unassigned,
          reason: 'Η αφαίρεση είναι η ίδια πράξη με αντίθετη φορά.',
        );
      });

      test('αφαίρεση ανάθεσης: ο πρώην υπεύθυνος μαθαίνει', () async {
        final id = await repo.createTask(newTask(assignedTo: kVlasis));
        await db.delete('task_notifications');

        await repo.assignTask(id, null);

        expect(
          (await inboxOf(kVlasis)).single.kind,
          TaskNotificationKind.unassigned,
        );
      });

      test('ίδια ανάθεση ξανά: τίποτα', () async {
        final id = await repo.createTask(newTask(assignedTo: kVlasis));
        await db.delete('task_notifications');

        await repo.assignTask(id, kVlasis);

        expect(await inboxOf(kVlasis), isEmpty);
      });

      test('ανάθεση στον εαυτό μου: καμία ειδοποίηση', () async {
        final id = await repo.createTask(newTask());

        await repo.assignTask(id, kVasilis);

        expect(await inboxOf(kVasilis), isEmpty);
      });
    });

    group('άλλες πύλες', () {
      test('δημιουργία ανατεθειμένη εξαρχής σε άλλον', () async {
        await repo.createTask(newTask(assignedTo: kVlasis));

        expect(
          (await inboxOf(kVlasis)).single.kind,
          TaskNotificationKind.assigned,
        );
      });

      test('η φόρμα αλλάζει υπεύθυνο', () async {
        final id = await repo.createTask(newTask(assignedTo: kVlasis));
        await db.delete('task_notifications');

        await repo.updateTask(
          (await taskOf(id)).copyWith(assignedOperatorId: kMaria),
        );

        expect(
          (await inboxOf(kMaria)).single.kind,
          TaskNotificationKind.assigned,
        );
        expect(
          (await inboxOf(kVlasis)).single.kind,
          TaskNotificationKind.unassigned,
        );
      });

      test('κλείσιμο ξένης: ο υπεύθυνος μαθαίνει', () async {
        final id = await repo.createTask(newTask(assignedTo: kVlasis));
        await db.delete('task_notifications');

        await repo.closeTask(id, 'Αντικαταστάθηκε το τόνερ.');

        final inbox = await inboxOf(kVlasis);
        expect(inbox.single.kind, TaskNotificationKind.closed);
        expect(inbox.single.actorOperatorId, kVasilis);
      });

      test('κλείσιμο ανανάθετης: μαθαίνει ο δημιουργός', () async {
        CurrentOperator.activate(_person(kVlasis, 'Βλάσης'));
        final id = await repo.createTask(newTask());
        await db.delete('task_notifications');

        CurrentOperator.activate(_person(kVasilis, 'Βασίλης'));
        await repo.closeTask(id, 'Το έλυσα εγώ.');

        expect(
          (await inboxOf(kVlasis)).single.kind,
          TaskNotificationKind.closed,
          reason:
              'Χωρίς ανάθεση, η εκκρεμότητα ανήκει σε αυτόν που την άνοιξε.',
        );
      });

      test('κλείσιμο δικής μου: καμία ειδοποίηση', () async {
        final id = await repo.createTask(newTask(assignedTo: kVasilis));

        await repo.closeTask(id, 'Αντικαταστάθηκε το τόνερ.');

        expect(await inboxOf(kVasilis), isEmpty);
      });

      test('ξανακλείσιμο ήδη κλειστής: δεν ξαναειδοποιεί', () async {
        final id = await repo.createTask(newTask(assignedTo: kVlasis));
        await repo.closeTask(id, 'Πρώτη λύση.');
        await db.delete('task_notifications');

        await repo.closeTask(id, 'Διορθωμένο κείμενο λύσης.');

        expect(await inboxOf(kVlasis), isEmpty);
      });
    });

    group('η ουρά', () {
      test('ο καθένας βλέπει μόνο τα δικά του', () async {
        final first = await repo.createTask(newTask());
        await repo.assignTask(first, kVlasis);
        final second = await repo.createTask(newTask());
        await repo.assignTask(second, kMaria);

        expect(await inboxOf(kVlasis), hasLength(1));
        expect(await inboxOf(kMaria), hasLength(1));
      });

      test('νεότερο πρώτο', () async {
        final first = await repo.createTask(newTask());
        await repo.assignTask(first, kVlasis);
        final second = await repo.createTask(newTask());
        await repo.assignTask(second, kVlasis);

        final inbox = await inboxOf(kVlasis);
        expect(inbox.map((n) => n.taskId), [second, first]);
      });

      test('διαγραμμένη εκκρεμότητα δεν αναγγέλλει τίποτα', () async {
        final id = await repo.createTask(newTask());
        await repo.assignTask(id, kVlasis);

        await db.update(
          'tasks',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );

        expect(await inboxOf(kVlasis), isEmpty);
      });

      test('το «Εντάξει» σβήνει τα δικά μου και μόνο', () async {
        final mine = await repo.createTask(newTask());
        await repo.assignTask(mine, kVlasis);
        final hers = await repo.createTask(newTask());
        await repo.assignTask(hers, kMaria);

        await notifications.clearFor(kVlasis);

        expect(await inboxOf(kVlasis), isEmpty);
        expect(await inboxOf(kMaria), hasLength(1));
      });
    });
  });
}

Operator _person(int id, String name) =>
    Operator(id: id, displayName: name, createdAt: DateTime(2026, 1, 1));
