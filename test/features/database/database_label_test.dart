// Το όνομα που δίνει ο χρήστης στη βάση: καθαρισμός και επιμονή.
//
// Ζει ΜΕΣΑ στη βάση ώστε να ταξιδεύει μαζί της — ένα αντίγραφο που θα ανοίξει
// σε άλλο μηχάνημα εξακολουθεί να ξέρει τι είναι.
//
//   flutter test test/features/database/database_label_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_identity_repository.dart';
import 'package:call_logger/features/database/services/database_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('καθαρισμός', () {
    test('κρατά ό,τι έγραψε ο χρήστης, χωρίς περιττά κενά', () {
      expect(normalizeDatabaseLabel('  Παραγωγή ΓΝΚ  '), 'Παραγωγή ΓΝΚ');
    });

    test('κενό, μόνο κενά και null σημαίνουν όλα «χωρίς όνομα»', () {
      expect(normalizeDatabaseLabel(null), isNull);
      expect(normalizeDatabaseLabel(''), isNull);
      expect(normalizeDatabaseLabel('   '), isNull);
      expect(
        normalizeDatabaseLabel('\n\t '),
        isNull,
        reason:
            'Μία αναπαράσταση της απουσίας — αλλιώς η οθόνη πρέπει να ξέρει '
            'δύο διαφορετικά «κενά».',
      );
    });

    test('ισοπεδώνει αλλαγές γραμμής και διπλά κενά', () {
      expect(
        normalizeDatabaseLabel('Παραγωγή\n\nΓΝΚ   Νοσοκομείο'),
        'Παραγωγή ΓΝΚ Νοσοκομείο',
        reason: 'Ετικέτα μιας γραμμής δεν κουβαλά μορφοποίηση.',
      );
    });

    test('κόβει ό,τι ξεπερνά το όριο, χωρίς να αφήνει κενό στο τέλος', () {
      final long = 'Α' * (kDatabaseLabelMaxLength + 20);
      final result = normalizeDatabaseLabel(long);

      expect(result, isNotNull);
      expect(result!.length, kDatabaseLabelMaxLength);
      expect(result.trimRight(), result);
    });
  });

  group('επιμονή μέσα στη βάση', () {
    late Directory tempDir;
    late DatabaseIdentityRepository repo;
    late Database db;

    setUp(() async {
      initSqfliteFfiForTests();
      await DatabaseHelper.instance.closeConnection();
      tempDir = await Directory.systemTemp.createTemp('db_label_');
      await DatabaseHelper.bindTestDatabaseFile('${tempDir.path}/labelled.db');
      db = await DatabaseHelper.instance.database;
      repo = DatabaseIdentityRepository(db);
    });

    tearDown(() async {
      await DatabaseHelper.instance.closeConnection();
      DatabaseHelper.releaseTestDatabaseBinding();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('βάση χωρίς όνομα απαντά null', () async {
      expect(await repo.readLabel(), isNull);
    });

    test('το όνομα επιζεί της εγγραφής και επιστρέφει καθαρό', () async {
      await repo.writeLabel('  Παραγωγή ΓΝΚ ');

      expect(await repo.readLabel(), 'Παραγωγή ΓΝΚ');
    });

    test('κενό όνομα σβήνει το προηγούμενο', () async {
      await repo.writeLabel('Δοκιμαστική');
      await repo.writeLabel('   ');

      expect(
        await repo.readLabel(),
        isNull,
        reason: 'Ο χρήστης που σβήνει το πεδίο ζητά «χωρίς όνομα».',
      );
    });

    test('δεύτερη εγγραφή αντικαθιστά, δεν προσθέτει', () async {
      await repo.writeLabel('Πρώτο');
      await repo.writeLabel('Δεύτερο');

      expect(await repo.readLabel(), 'Δεύτερο');
      final rows = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [kDatabaseLabelSettingsKey],
      );
      expect(rows, hasLength(1));
    });
  });
}
