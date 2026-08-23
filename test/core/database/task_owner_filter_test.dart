// Ποιος άνοιξε την εκκρεμότητα, και πώς φιλτράρεται η λίστα με βάση αυτό.
//
// Η πληροφορία «ποιος την άνοιξε» δεν ανακτάται ποτέ αργότερα: αν μια πόρτα
// δημιουργίας ξεφύγει, οι εκκρεμότητές της μένουν για πάντα αδέσποτες χωρίς να
// το πάρει κανείς είδηση. Εδώ φυλάγονται και οι δύο πόρτες, το φίλτρο, και το
// ότι οι μετρητές των chips μετρούν με τα ίδια κριτήρια με τη λίστα.
//
//   flutter test test/core/database/task_owner_filter_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/models/task_filter.dart';
import 'package:call_logger/core/models/owner_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('OwnerFilter — οι τρεις καταστάσεις', () {
    test('αποθηκεύεται και διαβάζεται χωρίς να μπερδεύονται μεταξύ τους', () {
      const everyone = OwnerFilter.everyone;
      const unassigned = OwnerFilter.unassigned;
      const mine = OwnerFilter.byOperator(7);

      expect(OwnerFilter.fromStorage(everyone.storageValue), everyone);
      expect(OwnerFilter.fromStorage(unassigned.storageValue), unassigned);
      expect(OwnerFilter.fromStorage(mine.storageValue), mine);

      expect(
        everyone,
        isNot(unassigned),
        reason:
            '«όλοι» και «κανενός» δεν είναι το ίδιο πράγμα — και τα δύο έχουν '
            'κενό id.',
      );
    });

    test('άγνωστη ή κενή αποθηκευμένη τιμή δεν μαντεύεται', () {
      expect(OwnerFilter.fromStorage(null), isNull);
      expect(OwnerFilter.fromStorage(''), isNull);
      expect(OwnerFilter.fromStorage('κατι'), isNull);
    });

    test('μόνο το «όλοι» δηλώνει απουσία περιορισμού', () {
      expect(OwnerFilter.everyone.isEveryone, isTrue);
      expect(OwnerFilter.unassigned.isEveryone, isFalse);
      expect(const OwnerFilter.byOperator(1).isEveryone, isFalse);
    });
  });

  group('Ποιος άνοιξε την εκκρεμότητα', () {
    late TasksRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('task_owner_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/task_owner.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('tasks');
      resetTestOperator();
      repo = TasksRepository();
    });

    tearDown(resetTestOperator);

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Task sample(String title) => Task(
      title: title,
      dueDate: '2026-09-01T10:00:00.000',
      status: 'open',
      origin: Task.originManualFab,
    );

    Future<int?> ownerOf(int taskId) async {
      final rows = await db.query(
        'tasks',
        columns: ['created_by_operator_id'],
        where: 'id = ?',
        whereArgs: [taskId],
      );
      return rows.single['created_by_operator_id'] as int?;
    }

    test('η χειροκίνητη δημιουργία σφραγίζεται με τον ενεργό χρήστη', () async {
      final me = activateTestOperator('Βασίλης', id: 11);

      final id = await repo.createTask(sample('Νέα εκκρεμότητα'));

      expect(await ownerOf(id), me.id);
    });

    test('η δημιουργία από κλήση σφραγίζεται κι αυτή', () async {
      final me = activateTestOperator('Βασίλης', id: 11);

      final id = await repo.createFromCallOnExecutor(
        db,
        row: <String, dynamic>{
          'title': 'Από κλήση',
          'due_date': '2026-09-01T10:00:00.000',
          'status': 'open',
          'origin': Task.originCallLinked,
        },
      );

      expect(
        await ownerOf(id),
        me.id,
        reason:
            'Δεύτερη πόρτα δημιουργίας — αν ξεφύγει, οι εκκρεμότητες που '
            'γεννιούνται από κλήσεις μένουν για πάντα αδέσποτες.',
      );
    });

    test('χωρίς αναγνωρισμένο χρήστη μένει κενή, δεν εφευρίσκεται', () async {
      final id = await repo.createTask(sample('Ανώνυμη'));

      expect(await ownerOf(id), isNull);
    });

    test('η αποθήκευση αλλαγών δεν σβήνει τη σφραγίδα', () async {
      final me = activateTestOperator('Βασίλης', id: 11);
      final id = await repo.createTask(sample('Αρχικός τίτλος'));
      final stored = (await repo.getFilteredTasks(
        TaskFilter(statuses: const [TaskStatus.open]),
      )).firstWhere((t) => t.id == id);

      await repo.updateTask(stored.copyWith(title: 'Αλλαγμένος τίτλος'));

      expect(
        await ownerOf(id),
        me.id,
        reason:
            'Μια διόρθωση κειμένου δεν αλλάζει ποιος άνοιξε την εκκρεμότητα.',
      );
    });
  });

  group('Το φίλτρο στη λίστα', () {
    late TasksRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('task_owner_q_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/task_owner_q.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('tasks');
      resetTestOperator();
      repo = TasksRepository();
    });

    tearDown(resetTestOperator);

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    /// Μία εκκρεμότητα του Βασίλη, μία του Βλάση, μία αδέσποτη.
    Future<({int vasilis, int vlasis})> seedThreeOwners() async {
      final vasilis = activateTestOperator('Βασίλης', id: 11);
      await repo.createTask(
        Task(
          title: 'Του Βασίλη',
          dueDate: '2026-09-01T10:00:00.000',
          status: 'open',
        ),
      );

      final vlasis = activateTestOperator('Βλάσης', id: 22);
      await repo.createTask(
        Task(
          title: 'Του Βλάση',
          dueDate: '2026-09-02T10:00:00.000',
          status: 'open',
        ),
      );

      resetTestOperator();
      await repo.createTask(
        Task(
          title: 'Αδέσποτη',
          dueDate: '2026-09-03T10:00:00.000',
          status: 'open',
        ),
      );

      return (vasilis: vasilis.id!, vlasis: vlasis.id!);
    }

    Future<List<String>> titlesFor(OwnerFilter owner) async {
      final tasks = await repo.getFilteredTasks(
        TaskFilter(statuses: const [TaskStatus.open], owner: owner),
      );
      return tasks.map((t) => t.title).toList()..sort();
    }

    test('«Όλοι» δεν κρύβει τίποτα', () async {
      await seedThreeOwners();

      expect(await titlesFor(OwnerFilter.everyone), [
        'Αδέσποτη',
        'Του Βασίλη',
        'Του Βλάση',
      ]);
    });

    test('ο κάθε χρήστης βλέπει μόνο τις δικές του', () async {
      final ids = await seedThreeOwners();

      expect(await titlesFor(OwnerFilter.byOperator(ids.vasilis)), [
        'Του Βασίλη',
      ]);
      expect(await titlesFor(OwnerFilter.byOperator(ids.vlasis)), [
        'Του Βλάση',
      ]);
    });

    test('οι αδέσποτες έχουν δικό τους φίλτρο και δεν χάνονται', () async {
      await seedThreeOwners();

      expect(await titlesFor(OwnerFilter.unassigned), ['Αδέσποτη']);
    });

    test(
      'η ανάθεση ΜΕΤΑΚΙΝΕΙ την ευθύνη — από τη μια λίστα στην άλλη',
      () async {
        final ids = await seedThreeOwners();
        final vasilisTask = (await repo.getFilteredTasks(
          TaskFilter(
            statuses: const [TaskStatus.open],
            owner: OwnerFilter.byOperator(ids.vasilis),
          ),
        )).single;

        await repo.assignTask(vasilisTask.id!, ids.vlasis);

        expect(
          await titlesFor(OwnerFilter.byOperator(ids.vasilis)),
          isEmpty,
          reason:
              'Η εκκρεμότητα δεν επιτρέπεται να ζει σε δύο λίστες: μόλις '
              'ανατέθηκε στον Βλάση, έφυγε από του Βασίλη.',
        );
        expect(await titlesFor(OwnerFilter.byOperator(ids.vlasis)), [
          'Του Βασίλη',
          'Του Βλάση',
        ]);
      },
    );

    test('η αφαίρεση ανάθεσης επιστρέφει την ευθύνη στον δημιουργό', () async {
      final ids = await seedThreeOwners();
      final vasilisTask = (await repo.getFilteredTasks(
        TaskFilter(
          statuses: const [TaskStatus.open],
          owner: OwnerFilter.byOperator(ids.vasilis),
        ),
      )).single;
      await repo.assignTask(vasilisTask.id!, ids.vlasis);

      await repo.assignTask(vasilisTask.id!, null);

      expect(await titlesFor(OwnerFilter.byOperator(ids.vasilis)), [
        'Του Βασίλη',
      ]);
    });

    test('ανατεθειμένη αδέσποτη ΔΕΝ είναι πια «Χωρίς χρήστη»', () async {
      final ids = await seedThreeOwners();
      final orphan = (await repo.getFilteredTasks(
        TaskFilter(
          statuses: const [TaskStatus.open],
          owner: OwnerFilter.unassigned,
        ),
      )).single;

      await repo.assignTask(orphan.id!, ids.vlasis);

      expect(
        await titlesFor(OwnerFilter.unassigned),
        isEmpty,
        reason:
            '«Χωρίς χρήστη» σημαίνει ούτε δημιουργό ούτε υπεύθυνο — μόλις '
            'απέκτησε υπεύθυνο, απέκτησε και λίστα.',
      );
      expect(
        await titlesFor(OwnerFilter.byOperator(ids.vlasis)),
        contains('Αδέσποτη'),
      );
    });

    test('χρήστης με ΜΟΝΟ ανατεθειμένες εμφανίζεται στις επιλογές', () async {
      final ids = await seedThreeOwners();
      final orphan = (await repo.getFilteredTasks(
        TaskFilter(
          statuses: const [TaskStatus.open],
          owner: OwnerFilter.unassigned,
        ),
      )).single;
      await repo.assignTask(orphan.id!, 77);

      expect(
        (await repo.getDistinctOwnerIds())..sort(),
        [ids.vasilis, ids.vlasis, 77],
        reason:
            'Αν οι επιλογές κοιτούσαν μόνο τους δημιουργούς, η λίστα του 77 '
            'θα υπήρχε αλλά δεν θα μπορούσε να επιλεγεί ποτέ.',
      );
    });

    test('συνδυάζεται με τα υπόλοιπα φίλτρα ως ΚΑΙ', () async {
      final ids = await seedThreeOwners();

      final tasks = await repo.getFilteredTasks(
        TaskFilter(
          statuses: const [TaskStatus.open],
          searchQuery: 'Βλάση',
          owner: OwnerFilter.byOperator(ids.vasilis),
        ),
      );

      expect(
        tasks,
        isEmpty,
        reason:
            'Η αναζήτηση βρίσκει του Βλάση, το φίλτρο δείχνει του Βασίλη — η '
            'τομή τους είναι άδεια.',
      );
    });

    test('οι μετρητές των chips μετρούν με τα ίδια κριτήρια', () async {
      final ids = await seedThreeOwners();

      final counts = await repo.getTaskCounts(
        TaskFilter(owner: OwnerFilter.byOperator(ids.vasilis)),
      );

      expect(
        counts[TaskStatus.open],
        1,
        reason:
            'Αν οι μετρητές αγνοούσαν το φίλτρο, το chip θα έλεγε «3» πάνω από '
            'λίστα με μία γραμμή.',
      );
    });

    test('η μέτρηση συμφωνεί πάντα με τη λίστα', () async {
      final ids = await seedThreeOwners();

      for (final owner in <OwnerFilter>[
        OwnerFilter.everyone,
        OwnerFilter.unassigned,
        OwnerFilter.byOperator(ids.vasilis),
      ]) {
        final filter = TaskFilter(
          statuses: const [TaskStatus.open],
          owner: owner,
        );
        expect(
          await repo.countFilteredTasks(filter),
          (await repo.getFilteredTasks(filter)).length,
          reason:
              'Η κενή οθόνη λέει «υπάρχουν N ακόμη» με βάση αυτή τη μέτρηση — '
              'αν αποκλίνει από τη λίστα, υπόσχεται εκκρεμότητες που δεν θα '
              'εμφανιστούν όταν πατηθεί το «Δείξε όλες».',
        );
      }
    });

    test(
      'οι διαθέσιμες επιλογές βγαίνουν από τα πραγματικά δεδομένα',
      () async {
        final ids = await seedThreeOwners();

        expect(
          (await repo.getDistinctOwnerIds())..sort(),
          [ids.vasilis, ids.vlasis]..sort(),
        );
        expect(await repo.hasUnassignedTasks(), isTrue);
      },
    );

    test('χωρίς αδέσποτες, η επιλογή τους δεν προσφέρεται', () async {
      activateTestOperator('Βασίλης', id: 11);
      await repo.createTask(
        Task(title: 'Μόνη', dueDate: '2026-09-01T10:00:00.000', status: 'open'),
      );

      expect(await repo.hasUnassignedTasks(), isFalse);
    });
  });

  group('Γρήγορη ανάθεση (assignTask)', () {
    late TasksRepository repo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('task_assign_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/task_assign.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('tasks');
      await db.delete('operators');
      resetTestOperator();
      repo = TasksRepository();
    });

    tearDown(resetTestOperator);

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> seedTask() async {
      activateTestOperator('Βασίλης', id: 11);
      return repo.createTask(
        Task(
          title: 'Προς ανάθεση',
          dueDate: '2026-09-01T10:00:00.000',
          status: 'open',
        ),
      );
    }

    Future<int> seedOperator(String name) async {
      return db.insert('operators', {
        'display_name': name,
        'is_admin': 0,
        'is_active': 1,
        'created_at': '2026-01-01T00:00:00.000',
      });
    }

    test(
      'γράφει τον υπεύθυνο και αφήνει ίχνος με ΟΝΟΜΑΤΑ, όχι αριθμούς',
      () async {
        final taskId = await seedTask();
        final vlasisId = await seedOperator('Βλάσης');
        await db.delete('audit_log');

        await repo.assignTask(taskId, vlasisId);

        final row = (await db.query(
          'tasks',
          where: 'id = ?',
          whereArgs: [taskId],
        )).single;
        expect(row['assigned_operator_id'], vlasisId);

        final audit = (await db.query('audit_log')).single;
        expect('${audit['old_values_json']}', contains('Χωρίς ανάθεση'));
        expect('${audit['new_values_json']}', contains('Βλάσης'));
        expect(
          '${audit['search_text']}',
          contains('υπευθυν'),
          reason:
              'Το «ποιος ανέλαβε τι» πρέπει να απαντιέται και από την αναζήτηση.',
        );
      },
    );

    test(
      'ίδια τιμή δεν γράφει τίποτα — ούτε στη βάση ούτε στο Ιστορικό',
      () async {
        final taskId = await seedTask();
        final vlasisId = await seedOperator('Βλάσης');
        await repo.assignTask(taskId, vlasisId);
        final before = (await db.query(
          'tasks',
          where: 'id = ?',
          whereArgs: [taskId],
        )).single;
        await db.delete('audit_log');

        await repo.assignTask(taskId, vlasisId);

        final after = (await db.query(
          'tasks',
          where: 'id = ?',
          whereArgs: [taskId],
        )).single;
        expect(after['updated_at'], before['updated_at']);
        expect(await db.query('audit_log'), isEmpty);
      },
    );

    test('η αποθήκευση από τη φόρμα δεν σβήνει καμία σφραγίδα', () async {
      final taskId = await seedTask();
      final vlasisId = await seedOperator('Βλάσης');
      await repo.assignTask(taskId, vlasisId);
      final stored = (await repo.getFilteredTasks(
        TaskFilter(statuses: const [TaskStatus.open]),
      )).firstWhere((t) => t.id == taskId);

      await repo.updateTask(
        stored.withFormValues(
          title: 'Αλλαγμένος τίτλος',
          description: null,
          dueDate: stored.dueDate,
          priority: stored.priority,
          callerId: null,
          userText: null,
          phoneText: null,
          departmentText: null,
          equipmentText: null,
          assignedOperatorId: stored.assignedOperatorId,
        ),
      );

      final row = (await db.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [taskId],
      )).single;
      expect(
        row['created_by_operator_id'],
        11,
        reason:
            'Το withFormValues χτίζει νέο αντικείμενο με ρητή λίστα πεδίων — '
            'αν ξεχάσει τη σφραγίδα, η πρώτη αποθήκευση την εξαφανίζει.',
      );
      expect(row['assigned_operator_id'], vlasisId);
    });

    test(
      'η αλλαγή υπευθύνου μέσα από τη φόρμα αφήνει ονομαστικό ίχνος',
      () async {
        final taskId = await seedTask();
        final vlasisId = await seedOperator('Βλάσης');
        final stored = (await repo.getFilteredTasks(
          TaskFilter(statuses: const [TaskStatus.open]),
        )).firstWhere((t) => t.id == taskId);
        await db.delete('audit_log');

        await repo.updateTask(
          stored.withFormValues(
            title: stored.title,
            description: null,
            dueDate: stored.dueDate,
            priority: stored.priority,
            callerId: null,
            userText: null,
            phoneText: null,
            departmentText: null,
            equipmentText: null,
            assignedOperatorId: vlasisId,
          ),
        );

        final audit = (await db.query('audit_log')).single;
        expect('${audit['old_values_json']}', contains('Χωρίς ανάθεση'));
        expect('${audit['new_values_json']}', contains('Βλάσης'));
      },
    );
  });

  group('Αναβάθμιση v53', () {
    late Database db;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await db.execute('''
        CREATE TABLE tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          status TEXT,
          is_deleted INTEGER DEFAULT 0
        )
      ''');
    });

    tearDown(() async {
      await db.close();
    });

    Future<Set<String>> columns() async {
      final info = await db.rawQuery('PRAGMA table_info(tasks)');
      return info.map((r) => r['name'] as String).toSet();
    }

    test('προσθέτει και τις δύο στήλες', () async {
      await migrateDatabaseToV53(db);

      expect(
        await columns(),
        containsAll(<String>['created_by_operator_id', 'assigned_operator_id']),
      );
    });

    test('οι υπάρχουσες εκκρεμότητες μένουν κενές, δεν αποδίδονται', () async {
      await db.insert('tasks', {'title': 'Παλιά', 'status': 'open'});

      await migrateDatabaseToV53(db);

      final row = (await db.query('tasks')).single;
      expect(row['created_by_operator_id'], isNull);
      expect(row['title'], 'Παλιά');
    });

    test('ξανατρέχει χωρίς παρενέργειες', () async {
      await db.insert('tasks', {'title': 'Παλιά', 'status': 'open'});

      await migrateDatabaseToV53(db);
      await migrateDatabaseToV53(db);

      expect((await db.query('tasks')).length, 1);
      expect(await columns(), contains('created_by_operator_id'));
    });
  });
}
