// Το Ιστορικό φιλτράρει σε τμήμα, υπάλληλο και εξοπλισμό — όπως τα Στατιστικά.
//
// Χωρίς αυτά, το «Προβολή όλων» των Στατιστικών δεν έχει πού να ακουμπήσει τα
// φίλτρα του Πίνακα Ελέγχου και τα πετάει: ο χρήστης κοιτάζει ένα τμήμα, πατά
// «Προβολή όλων» και βλέπει ολόκληρο το νοσοκομείο.
//
// Ο μετρητής «Χ από Υ» μετρά με τα ΙΔΙΑ κριτήρια — αλλιώς λέει «12 από 340»
// ενώ το φίλτρο περιορίζει σε 40.
//
//   flutter test test/core/database/history_entity_filters_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late CallsRepository repo;
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp(
      'history_entity_filters_',
    );
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/history_filters.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('calls');
    resetTestOperator();
    repo = CallsRepository(db);
  });

  tearDown(resetTestOperator);

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  /// Κλήσεις με ελεύθερο κείμενο — η συνηθισμένη παλιά εγγραφή, χωρίς σύνδεση
  /// με τον κατάλογο. Αν το φίλτρο δουλεύει εδώ, δουλεύει και στη σύνδεση.
  Future<void> seedCalls() async {
    await repo.insertCall(
      CallModel(
        callerText: 'Βαρβάρα Ψαρρά',
        phoneText: '2517',
        departmentText: 'Αιματολογικό',
        equipmentText: '5010',
        issue: 'Δεν ανοίγει',
        status: 'completed',
      ),
    );
    await repo.insertCall(
      CallModel(
        callerText: 'Γεωργία Παπαγεωργίου',
        phoneText: '2540',
        departmentText: 'Γραφείο Κίνησης',
        equipmentText: '3495',
        issue: 'Αργεί',
        status: 'completed',
      ),
    );
  }

  Future<List<String>> issuesWhere({
    String? department,
    String? userName,
    String? equipmentCode,
  }) async {
    final rows = await repo.getHistoryCalls(
      department: department,
      userName: userName,
      equipmentCode: equipmentCode,
    );
    return rows.map((r) => (r['issue'] as String?) ?? '').toList()..sort();
  }

  group('Φίλτρα οντότητας στο Ιστορικό', () {
    test('χωρίς φίλτρο επιστρέφονται όλες', () async {
      await seedCalls();
      expect(await issuesWhere(), ['Αργεί', 'Δεν ανοίγει']);
    });

    test('το τμήμα κρατά μόνο τις δικές του κλήσεις', () async {
      await seedCalls();
      expect(await issuesWhere(department: 'Αιματολογικό'), ['Δεν ανοίγει']);
    });

    test(
      'ο υπάλληλος βρίσκεται και από το όνομα και από το τηλέφωνο',
      () async {
        await seedCalls();
        expect(await issuesWhere(userName: 'Ψαρρά'), ['Δεν ανοίγει']);
        expect(await issuesWhere(userName: '2540'), ['Αργεί']);
      },
    );

    test('ο εξοπλισμός βρίσκεται και με μέρος του κωδικού', () async {
      await seedCalls();
      expect(await issuesWhere(equipmentCode: '5010'), ['Δεν ανοίγει']);
      expect(await issuesWhere(equipmentCode: '349'), ['Αργεί']);
    });

    test('δύο φίλτρα στενεύουν μαζί, δεν προσθέτουν', () async {
      await seedCalls();
      expect(
        await issuesWhere(department: 'Αιματολογικό', equipmentCode: '3495'),
        isEmpty,
        reason:
            'Τα φίλτρα ενώνονται με ΚΑΙ — αλλιώς ο χρήστης βλέπει κλήσεις που '
            'δεν ζήτησε.',
      );
    });

    test('ο μετρητής μετρά με τα ίδια κριτήρια', () async {
      await seedCalls();

      expect(await repo.getHistoryCallCount(), 2);
      expect(
        await repo.getHistoryCallCount(department: 'Αιματολογικό'),
        1,
        reason:
            'Ο μετρητής τροφοδοτεί το «Χ από Υ»· αν αγνοεί τα φίλτρα, το Υ '
            'μετρά άλλο σύνολο από αυτό που βλέπει ο χρήστης.',
      );
    });
  });
}
