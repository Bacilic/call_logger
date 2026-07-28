// Ατομικότητα ενημέρωσης + audit σε εκκρεμότητες και κλήσεις.
//
// Συμβόλαιο: κάθε σύνθετη μετάβαση δεδομένων εκτελείται σε ΜΙΑ συναλλαγή,
// και το «πριν» του audit διαβάζεται μέσα σε αυτήν.
//
// Σημείωση ειλικρίνειας: η πραγματική διεμπλοκή (ξένη εγγραφή ανάμεσα στην
// ανάγνωση του «πριν» και στη συναλλαγή) δεν αναπαράγεται αξιόπιστα σε unit
// test· τα τεστ του «πριν» φυλάνε τη δομική ιδιότητα «το παλιό διαβάζεται
// από τη βάση, όχι από το αντικείμενο του καλούντα».
//
//   flutter test test/core/database/tasks_calls_audit_atomicity_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/core/errors/task_save_exception.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('ατομικότητα ενημέρωσης + audit (εκκρεμότητες/κλήσεις)', () {
    late Database db;
    late TasksRepository tasks;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('tasks_audit_atomic_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/audit_atomic.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('tasks');
      await db.delete('calls');
      tasks = TasksRepository();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insertOpenTask() => tasks.createTask(
      Task(
        title: 'Έλεγχος ατομικότητας',
        dueDate: '2026-07-28T10:00:00.000',
        status: 'open',
      ),
    );

    Map<String, dynamic> decodeOldValues(Map<String, dynamic> auditRow) {
      final raw = auditRow['old_values_json'] as String?;
      expect(raw, isNotNull, reason: 'το audit πρέπει να έχει old_values_json');
      return Map<String, dynamic>.from(jsonDecode(raw!) as Map);
    }

    test('closeTask: αποτυχία audit αφήνει την εκκρεμότητα ΑΝΟΙΧΤΗ '
        'και δίνει ειλικρινές σφάλμα (όχι σιωπηλό μισό αποτέλεσμα)', () async {
      final id = await insertOpenTask();
      await db.execute('ALTER TABLE audit_log RENAME TO audit_log_hidden');
      try {
        await expectLater(
          tasks.closeTask(id, 'δοκιμαστική λύση'),
          throwsA(isA<TaskSaveException>()),
        );
      } finally {
        await db.execute('ALTER TABLE audit_log_hidden RENAME TO audit_log');
      }

      final row = (await db.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [id],
      )).first;
      expect(
        row['status'],
        'open',
        reason: 'χωρίς audit δεν επιτρέπεται να κλείσει — κοινή συναλλαγή',
      );
    });

    test('closeTask: κλείσιμο και audit μαζί, με το πραγματικό παλιό status',
        () async {
      final id = await insertOpenTask();
      await db.delete('audit_log');

      await tasks.closeTask(id, 'η λύση');

      final row = (await db.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [id],
      )).first;
      expect(row['status'], 'closed');
      expect(row['solution_notes'], 'η λύση');

      final audits = await db.query(
        'audit_log',
        where: "action = 'ΚΛΕΙΣΙΜΟ ΕΚΚΡΕΜΟΤΗΤΑΣ'",
      );
      expect(audits, hasLength(1));
      expect(decodeOldValues(audits.single)['status'], 'open');
    });

    test('updateTask: το «πριν» του audit είναι η τρέχουσα εγγραφή της βάσης, '
        'όχι το αντικείμενο του καλούντα', () async {
      final id = await insertOpenTask();
      await db.update(
        'tasks',
        {'status': 'snoozed'},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.delete('audit_log');

      await tasks.updateTask(
        Task(
          id: id,
          title: 'Έλεγχος ατομικότητας',
          dueDate: '2026-07-28T10:00:00.000',
          status: 'closed',
        ),
      );

      final audits = await db.query('audit_log');
      expect(audits, hasLength(1));
      expect(decodeOldValues(audits.single)['status'], 'snoozed');
    });

    test('updateCall: το «πριν» του audit είναι η τρέχουσα εγγραφή της βάσης',
        () async {
      final calls = CallsRepository(db);
      final id = await calls.insertCall(
        CallModel(
          date: '2026-07-28',
          time: '10:00',
          issue: 'αρχικό θέμα',
          status: 'pending',
        ),
      );
      await db.update(
        'calls',
        {'issue': 'αλλαγμένο από συνάδελφο'},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.delete('audit_log');

      await calls.updateCall(
        CallModel(
          id: id,
          date: '2026-07-28',
          time: '10:00',
          issue: 'τελικό θέμα',
          status: 'pending',
          lansweeperState: 'unsent',
        ),
      );

      final audits = await db.query('audit_log');
      expect(audits, hasLength(1));
      expect(
        decodeOldValues(audits.single)['issue'],
        'αλλαγμένο από συνάδελφο',
      );
    });
  });
}
