// Το φίλτρο «Καλούντας» ταιριάζει τον άνθρωπο, όχι λέξη μέσα στην κλήση.
//
// Ήταν δεμένο στο ευρετήριο αναζήτησης — το ίδιο κείμενο που τροφοδοτεί τη
// γενική αναζήτηση — οπότε έφερνε κλήσεις όπου το όνομα απλώς αναφερόταν στην
// περιγραφή, και δεχόταν λέξεις που δεν είναι καν άνθρωπος.
//
//   flutter test test/core/database/caller_filter_matches_the_person_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

void main() {
  late CallsRepository calls;
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('caller_filter_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/caller_filter.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('calls');
    resetTestOperator();
    calls = CallsRepository(db);
  });

  tearDown(resetTestOperator);

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<void> seedCalls() async {
    await calls.insertCall(
      CallModel(
        callerText: 'Βαρβάρα Ψαρρά',
        departmentText: 'Αιματολογικό',
        category: 'Medico',
        issue: 'Δεν ανοίγει το πρόγραμμα',
        status: 'completed',
        duration: 300,
      ),
    );
    // Άλλος καλών — αλλά το όνομα της Βαρβάρας γράφτηκε μέσα στην περιγραφή.
    await calls.insertCall(
      CallModel(
        callerText: 'Γεωργία Παπαγεωργίου',
        departmentText: 'Γραφείο Κίνησης',
        category: 'Εκτυπωτής',
        issue: 'Το είχε αναφέρει και η Βαρβάρα Ψαρρά',
        status: 'completed',
        duration: 120,
      ),
    );
  }

  group('Φίλτρο καλούντα', () {
    test(
      'φέρνει μόνο τις κλήσεις ΤΟΥ καλούντα, όχι όσες τον αναφέρουν',
      () async {
        await seedCalls();

        final rows = await calls.getHistoryCalls(userName: 'Βαρβάρα Ψαρρά');

        expect(
          rows.length,
          1,
          reason: greekExpectMsg(
            'Η κλήση της Γεωργίας αναφέρει τη Βαρβάρα στην περιγραφή, '
            'αλλά δεν είναι δική της κλήση',
          ),
        );
        expect(rows.single['issue'], 'Δεν ανοίγει το πρόγραμμα');
      },
    );

    test('δεν δέχεται λέξη που δεν είναι άνθρωπος', () async {
      await seedCalls();

      final rows = await calls.getHistoryCalls(userName: 'Εκτυπωτής');

      expect(
        rows,
        isEmpty,
        reason: greekExpectMsg(
          'Η «Εκτυπωτής» είναι κατηγορία, όχι καλών — το φίλτρο προσώπου '
          'δεν πρέπει να την αναγνωρίζει',
        ),
      );
    });

    test('βρίσκει και τον καλούντα που είναι καρτέλα του Καταλόγου', () async {
      final userRows = await db.rawQuery(
        'SELECT id FROM users WHERE first_name = ? AND last_name = ?',
        [kTestUserFirstName, kTestUserLastName],
      );
      final callerId = userRows.single['id'] as int;
      await calls.insertCall(
        CallModel(
          callerId: callerId,
          departmentText: kTestDepartmentName,
          issue: 'Κλήση συνδεδεμένου υπαλλήλου',
          status: 'completed',
          duration: 60,
        ),
      );

      final rows = await calls.getHistoryCalls(
        userName: '$kTestUserFirstName $kTestUserLastName',
      );

      expect(rows.length, 1);
      expect(rows.single['issue'], 'Κλήση συνδεδεμένου υπαλλήλου');
    });
  });
}
