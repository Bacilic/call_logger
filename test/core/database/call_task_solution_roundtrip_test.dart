// Η λύση ταξιδεύει και στις δύο κατευθύνσεις του δεσμού κλήσης–εκκρεμότητας.
//
// Το συμβόλαιο: ό,τι γράφεται μία φορά φαίνεται και στις δύο πλευρές, και η
// αλυσίδα «από πού ξεκίνησε → πώς έκλεισε» δεν σβήνεται ποτέ.
//
//   flutter test test/core/database/call_task_solution_roundtrip_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Λύση κλήσης ↔ εκκρεμότητας', () {
    late Database db;
    late TasksRepository tasks;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('call_task_solution_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/roundtrip.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('tasks');
      await db.delete('calls');
      tasks = TasksRepository();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> seedCall({String? solution}) => db.insert('calls', {
      'date': '2026-08-26',
      'time': '10:00',
      'issue': 'Δεν μπορώ να τιμολογήσω',
      'solution': solution,
      'status': 'pending',
      'is_deleted': 0,
    });

    test('κλήση → εκκρεμότητα: η λύση ακολουθεί στις σημειώσεις', () async {
      final row = await tasks.buildCreateFromCallRow(
        callId: null,
        callerName: 'Βαρβάρα',
        description: 'Δεν μπορώ να τιμολογήσω',
        callSolution: 'Να γίνει αίτημα στην DataMed',
        callDate: DateTime(2026, 8, 26, 10),
      );

      expect(
        row['description'],
        'Δεν μπορώ να τιμολογήσω\n\nΛύση: Να γίνει αίτημα στην DataMed',
      );
      expect(
        row['title'],
        isNot(contains('DataMed')),
        reason: 'ο τίτλος χτίζεται από τη σκέτη περιγραφή, χωρίς τα βήματα',
      );
    });

    test('χωρίς λύση η περιγραφή μένει όπως ήταν', () async {
      final row = await tasks.buildCreateFromCallRow(
        callId: null,
        callerName: 'Βαρβάρα',
        description: 'Δεν μπορώ να τιμολογήσω',
        callDate: DateTime(2026, 8, 26, 10),
      );

      expect(row['description'], 'Δεν μπορώ να τιμολογήσω');
    });

    test('κλείσιμο εκκρεμότητας: η λύση προστίθεται στην κλήση', () async {
      final callId = await seedCall(solution: 'Να γίνει αίτημα στην DataMed');
      final row = await tasks.buildCreateFromCallRow(
        callId: callId,
        callerName: 'Βαρβάρα',
        description: 'Δεν μπορώ να τιμολογήσω',
        callDate: DateTime(2026, 8, 26, 10),
      );
      final taskId = await db.insert('tasks', row);

      await tasks.closeTask(
        taskId,
        'Η DataMed δημιούργησε μηχανισμό τιμολογίων',
        force: true,
      );

      final call = (await db.query(
        'calls',
        where: 'id = ?',
        whereArgs: [callId],
      )).single;
      expect(
        call['solution'],
        'Να γίνει αίτημα στην DataMed\n\n'
        'Από την εκκρεμότητα: Η DataMed δημιούργησε μηχανισμό τιμολογίων',
        reason: 'τα πρώτα βήματα μένουν — η αλυσίδα διαβάζεται ολόκληρη',
      );
      expect(
        call['search_index'].toString(),
        contains('μηχανισμο'),
        reason: 'χωρίς ξαναχτίσιμο ευρετηρίου η νέα λύση δεν θα βρισκόταν ποτέ',
      );
    });

    test('το ξανακλείσιμο δεν διπλογράφει στην κλήση', () async {
      final callId = await seedCall();
      final row = await tasks.buildCreateFromCallRow(
        callId: callId,
        callerName: 'Βαρβάρα',
        description: 'Δεν μπορώ να τιμολογήσω',
        callDate: DateTime(2026, 8, 26, 10),
      );
      final taskId = await db.insert('tasks', row);

      await tasks.closeTask(taskId, 'Λύθηκε από τη DataMed', force: true);
      await tasks.closeTask(taskId, 'Λύθηκε από τη DataMed', force: true);

      final call = (await db.query(
        'calls',
        where: 'id = ?',
        whereArgs: [callId],
      )).single;
      expect(
        (call['solution'] as String).split('DataMed').length - 1,
        1,
        reason: 'το ίδιο κείμενο δεν μπαίνει δεύτερη φορά',
      );
    });

    test('εκκρεμότητα χωρίς κλήση δεν αγγίζει τίποτα', () async {
      final row = await tasks.buildCreateFromCallRow(
        callId: null,
        callerName: 'Βαρβάρα',
        description: 'Αυτόνομη εκκρεμότητα',
        callDate: DateTime(2026, 8, 26, 10),
      );
      final taskId = await db.insert('tasks', row);

      await tasks.closeTask(taskId, 'Έγινε', force: true);

      expect(await db.query('calls'), isEmpty);
    });

    test('ο ορισμός γράφεται στο Ιστορικό της κλήσης', () async {
      final callId = await seedCall();
      final row = await tasks.buildCreateFromCallRow(
        callId: callId,
        callerName: 'Βαρβάρα',
        description: 'Δεν μπορώ να τιμολογήσω',
        callDate: DateTime(2026, 8, 26, 10),
      );
      final taskId = await db.insert('tasks', row);

      await tasks.closeTask(taskId, 'Λύθηκε από τη DataMed', force: true);

      final entries = await db.query(
        'audit_log',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['call', callId],
      );
      expect(entries, isNotEmpty);
    });

    test('η προσθήκη δουλεύει και μόνη της, μέσα σε ξένη συναλλαγή', () async {
      final callId = await seedCall(solution: 'Πρώτα βήματα');

      await db.transaction((txn) async {
        await CallsRepository(db).appendSolutionFromTask(
          txn,
          callId: callId,
          taskSolution: 'Το φινάλε',
        );
      });

      final call = (await db.query(
        'calls',
        where: 'id = ?',
        whereArgs: [callId],
      )).single;
      expect(
        call['solution'],
        'Πρώτα βήματα\n\nΑπό την εκκρεμότητα: Το φινάλε',
      );
    });
  });
}
