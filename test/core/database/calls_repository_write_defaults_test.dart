// Συνέπεια προεπιλογών insert/update κλήσης: κοινός χάρτης πεδίων ώστε
// ελλιπές CallModel να παίρνει τις ίδιες προεπιλογές και στις δύο ροές,
// αντί να σκάει σε NOT NULL constraint με γενικό μήνυμα.
//
//   flutter test test/core/database/calls_repository_write_defaults_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('προεπιλογές εγγραφής κλήσης — insert και update συμφωνούν', () {
    late Database db;
    late CallsRepository calls;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('calls_defaults_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/defaults.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('calls');
      calls = CallsRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('ενημέρωση με ελλιπές αντικείμενο (χωρίς status/lansweeper_state) '
        'παίρνει τις ίδιες προεπιλογές με τη δημιουργία', () async {
      final id = await calls.insertCall(
        CallModel(
          date: '2026-07-28',
          time: '10:00',
          issue: 'αρχικό θέμα',
          status: 'pending',
        ),
      );

      await calls.updateCall(
        CallModel(
          id: id,
          date: '2026-07-28',
          time: '10:00',
          issue: 'τελικό θέμα',
        ),
      );

      final row = (await db.query(
        'calls',
        where: 'id = ?',
        whereArgs: [id],
      )).first;
      expect(row['issue'], 'τελικό θέμα');
      expect(
        row['status'],
        'completed',
        reason: 'ίδια προεπιλογή με τη δημιουργία',
      );
      expect(
        row['lansweeper_state'],
        'unsent',
        reason: 'ίδια προεπιλογή με τη δημιουργία — όχι NOT NULL σφάλμα',
      );
    });

    test('η δημιουργία κρατά τις γνωστές προεπιλογές της', () async {
      final id = await calls.insertCall(CallModel(issue: 'χωρίς πεδία'));
      final row = (await db.query(
        'calls',
        where: 'id = ?',
        whereArgs: [id],
      )).first;
      expect(row['status'], 'completed');
      expect(row['lansweeper_state'], 'unsent');
      expect(row['is_deleted'], 0);
      expect(row['date'], isNotNull);
      expect(row['time'], isNotNull);
    });
  });
}
