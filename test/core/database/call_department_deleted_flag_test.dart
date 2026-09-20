// Πότε η κλήση δηλώνει ότι το τμήμα της έχει διαγραφεί.
//
// Το τμήμα δεν κρατά σύνδεση στην κλήση — μόνο όνομα. Άρα ένα όνομα που δεν
// ταιριάζει πουθενά μπορεί να είναι διαγραμμένο τμήμα Ή ορθογραφικό λάθος. Στη
// βάση του νοσοκομείου τα δεύτερα είναι 16 και τα πρώτα 1: αν το κριτήριο δεν
// τα ξεχώριζε, το σήμα θα πνιγόταν στον θόρυβο.
//
//   flutter test test/core/database/call_department_deleted_flag_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/call_department_deleted_flag.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late CallsRepository calls;
  late Directory tempDir;

  setUpAll(() async {
    initSqfliteFfiForTests();
    tempDir = await Directory.systemTemp.createTemp('dept_deleted_flag_');
    await DatabaseHelper.bindTestDatabaseFile('${tempDir.path}/t.db');
    db = await DatabaseHelper.instance.database;
    calls = CallsRepository(db);
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.closeConnection();
    DatabaseHelper.releaseTestDatabaseBinding();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await db.delete('calls');
    await db.delete('departments');
  });

  Future<void> insertDepartment(String name, {required bool deleted}) async {
    await db.insert('departments', {
      'name': name,
      'name_key': SearchTextNormalizer.normalizeForSearch(name),
      'is_deleted': deleted ? 1 : 0,
    });
  }

  Future<CallModel> callWithDepartment(String departmentText) async {
    await db.insert('calls', {
      'date': '2026-09-20',
      'time': '10:00',
      'department_text': departmentText,
      'issue': 'δοκιμή',
      'status': 'completed',
      'is_deleted': 0,
    });
    final rows = await calls.getRecentCalls(limit: 1);
    return CallModel.fromMap(rows.single);
  }

  test('το τμήμα διαγράφηκε → η κλήση το δηλώνει', () async {
    await insertDepartment('Φαρμακείο', deleted: true);

    final call = await callWithDepartment('Φαρμακείο');

    expect(call.departmentLinkedDeleted, isTrue);
    expect(call.departmentText, 'Φαρμακείο');
  });

  test('ζωντανό τμήμα → καμία ένδειξη', () async {
    await insertDepartment('Φαρμακείο', deleted: false);

    expect(
      (await callWithDepartment('Φαρμακείο')).departmentLinkedDeleted,
      isFalse,
    );
  });

  test('ορθογραφικό λάθος ΔΕΝ είναι διαγραφή — το κρίσιμο ξεχώρισμα', () async {
    await insertDepartment('Πρωτόκολλο', deleted: false);

    // «Προτόκωλο»: όνομα που δεν υπήρξε ποτέ, ούτε ζωντανό ούτε διαγραμμένο.
    final call = await callWithDepartment('Προτόκωλο');

    expect(
      call.departmentLinkedDeleted,
      isFalse,
      reason:
          'Χωρίς αυτόν τον όρο, 16 κλήσεις με ορθογραφικά θα δήλωναν ψευδώς '
          'διαγραμμένο τμήμα.',
    );
  });

  test(
    'δύο τμήματα με το ίδιο όνομα δεν γίνονται — το εμποδίζει η βάση',
    () async {
      await insertDepartment('Αιμοδοσία', deleted: true);

      // Ο δεύτερος όρος του κριτηρίου («κανένα ζωντανό») δεν φυλάει σενάριο που
      // συμβαίνει καθημερινά: ο μοναδικός δείκτης του Καταλόγου δεν επιτρέπει
      // διαγραμμένο και ζωντανό τμήμα με το ίδιο όνομα. Μένει ως άμυνα, και το
      // τεστ καταγράφει γιατί δεν μπορεί να δοκιμαστεί αλλιώς.
      await expectLater(
        insertDepartment('Αιμοδοσία', deleted: false),
        throwsA(anything),
      );

      expect(
        (await callWithDepartment('Αιμοδοσία')).departmentLinkedDeleted,
        isTrue,
      );
    },
  );

  test('κλήση χωρίς τμήμα δεν δηλώνει τίποτα', () async {
    await insertDepartment('Φαρμακείο', deleted: true);

    expect((await callWithDepartment('  ')).departmentLinkedDeleted, isFalse);
  });

  test('το κριτήριο ζει σε ένα σημείο και ονομάζει τη στήλη του', () {
    expect(kCallDepartmentIsDeletedSql, contains('department_is_deleted'));
    expect(kCallDepartmentIsDeletedSql, contains('dept_del'));
    expect(
      kCallDepartmentIsDeletedSql,
      contains('dept_live'),
      reason: 'Χωρίς τον όρο του ζωντανού, το ορθογραφικό θα περνούσε.',
    );
  });
}
