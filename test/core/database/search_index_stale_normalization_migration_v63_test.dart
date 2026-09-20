// Το ευρετήριο αναζήτησης κάθε κλήσης και εκκρεμότητας γράφεται ΜΙΑ φορά, τη
// στιγμή της καταγραφής. Στις 30/06/2026 η κανονικοποίηση άρχισε να μετατρέπει
// το τελικό «ς» σε «σ» — και όσα είχαν ήδη γραφτεί κράτησαν την παλιά μορφή.
// Από τότε η πληκτρολόγηση «Χρήστης» ψάχνει «χρηστησ» ενώ το αποθηκευμένο λέει
// «χρηστης»: η αναζήτηση αδειάζει. Η αναβάθμιση v63 τα ξαναχτίζει.
//
//   flutter test test/core/database/search_index_stale_normalization_migration_v63_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  group('Αναβάθμιση v63 — ευρετήρια σε παλιό κανόνα κανονικοποίησης', () {
    registerCallLoggerIsolatedDatabaseHooks();

    /// Γυρίζει το ευρετήριο μιας γραμμής στη μορφή που είχε πριν τις
    /// 30/06/2026: το τελικό «ς» γραφόταν αυτούσιο.
    Future<void> makeSearchIndexLegacy(String table, int id) async {
      final db = await DatabaseHelper.instance.database;
      await db.rawUpdate(
        "UPDATE $table SET search_index = REPLACE(search_index, 'σ ', 'ς ') "
        "WHERE id = ?",
        [id],
      );
    }

    Future<void> writeLegacyIndex(String table, int id, String text) async {
      final db = await DatabaseHelper.instance.database;
      await db.update(
        table,
        {'search_index': text},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    Future<int> callsMatching(String term) async {
      final db = await DatabaseHelper.instance.database;
      final rows = await CallsRepository(
        db,
      ).getHistoryCalls(keyword: SearchTextNormalizer.normalizeForSearch(term));
      return rows.length;
    }

    test(
      'κλήση με παλιό ευρετήριο: ολόκληρη η λέξη δεν βρίσκει τίποτα, μετά την αναβάθμιση τη βρίσκει',
      () async {
        final db = await DatabaseHelper.instance.database;
        final callId = await CallsRepository(db).insertCall(
          CallModel(
            phoneText: kTestPhoneDigits,
            callerText: '$kTestUserFirstName $kTestUserLastName',
            issue: 'Κόλλησε η εφαρμογή',
            status: 'completed',
          ),
        );

        // Φρέσκο ευρετήριο: και οι δύο γραφές βρίσκουν την κλήση.
        expect(await callsMatching(kTestUserLastName), 1);

        await writeLegacyIndex(
          'calls',
          callId,
          'χρηστης δοκιμη κολλησε η εφαρμογη',
        );

        expect(
          await callsMatching(kTestUserLastName),
          0,
          reason:
              'Το σφάλμα: το αποθηκευμένο ευρετήριο κρατά «χρηστης» ενώ η '
              'πληκτρολόγηση ψάχνει πλέον «χρηστησ».',
        );
        expect(
          await callsMatching('Χρήστη'),
          1,
          reason: 'Χωρίς το τελικό γράμμα η ίδια αναζήτηση πετυχαίνει.',
        );

        await migrateDatabaseToV63(db);

        expect(
          await callsMatching(kTestUserLastName),
          1,
          reason: 'Μετά την αναβάθμιση ολόκληρη η λέξη βρίσκει την κλήση.',
        );
      },
    );

    test('εκκρεμότητα με παλιό ευρετήριο ξαναβρίσκεται', () async {
      final db = await DatabaseHelper.instance.database;
      final taskId = await TasksRepository().createTask(
        Task(
          title: 'Να ενημερωθεί ο Χρήστης',
          dueDate: '2026-12-31',
          status: 'open',
        ),
      );

      await writeLegacyIndex('tasks', taskId, 'να ενημερωθει ο χρηστης');

      Future<int> tasksMatching(String term) async {
        final rows = await db.query(
          'tasks',
          where: 'search_index LIKE ?',
          whereArgs: ['%${SearchTextNormalizer.normalizeForSearch(term)}%'],
        );
        return rows.length;
      }

      expect(await tasksMatching('Χρήστης'), 0);

      await migrateDatabaseToV63(db);

      expect(
        await tasksMatching('Χρήστης'),
        1,
        reason: 'Η εκκρεμότητα ξαναβρίσκεται με ολόκληρη τη λέξη.',
      );
    });

    test('η αναβάθμιση ξανατρέχει χωρίς παρενέργειες', () async {
      final db = await DatabaseHelper.instance.database;
      final callId = await CallsRepository(db).insertCall(
        CallModel(
          phoneText: kTestPhoneDigits,
          callerText: kTestUserLastName,
          issue: 'Δεύτερη καταγραφή',
          status: 'completed',
        ),
      );
      await makeSearchIndexLegacy('calls', callId);

      await migrateDatabaseToV63(db);
      final afterFirst = await db.query(
        'calls',
        columns: ['search_index'],
        where: 'id = ?',
        whereArgs: [callId],
      );

      await migrateDatabaseToV63(db);
      final afterSecond = await db.query(
        'calls',
        columns: ['search_index'],
        where: 'id = ?',
        whereArgs: [callId],
      );

      expect(
        afterSecond.single['search_index'],
        afterFirst.single['search_index'],
      );
      expect(await callsMatching('Δεύτερη καταγραφή'), 1);
    });

    test('η αναβάθμιση δεν χάνει το περιεχόμενο της κλήσης', () async {
      final db = await DatabaseHelper.instance.database;
      final callId = await CallsRepository(db).insertCall(
        CallModel(
          phoneText: kTestPhoneDigits,
          callerText: kTestUserLastName,
          issue: 'Το ticket 17438 έμεινε ανοιχτό',
          status: 'completed',
        ),
      );
      await writeLegacyIndex('calls', callId, 'χρηστης παλιο ευρετηριο');

      await migrateDatabaseToV63(db);

      final row = (await db.query(
        'calls',
        where: 'id = ?',
        whereArgs: [callId],
      )).single;
      expect(row['issue'], 'Το ticket 17438 έμεινε ανοιχτό');
      expect(await callsMatching('17438'), 1);
    });
  });
}
