// Ο χτύπος «είμαι εδώ»: ακολουθεί την ταυτότητα, χωρίς να τον καλεί καμία οθόνη.
//
//   flutter test test/core/services/operator_presence_heartbeat_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_presence_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/operator_presence_heartbeat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

Operator _operator(int id) =>
    Operator(id: id, displayName: 'Χρήστης $id', createdAt: DateTime(2026, 8));

void main() {
  group('Χτύπος παρουσίας', () {
    late Database db;
    late OperatorPresenceRepository repository;
    final heartbeat = OperatorPresenceHeartbeat.instance;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('presence_heartbeat_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/presence.db');
      db = await DatabaseHelper.instance.database;
      repository = OperatorPresenceRepository(db);
    });

    setUp(() async {
      await db.delete(OperatorPresenceRepository.tableName);
      CurrentOperator.reset();
      OperatorPresenceHeartbeat.stationNameReader = () => 'ΔΟΚΙΜΗ-01';
    });

    tearDown(() {
      heartbeat.stop();
      CurrentOperator.reset();
    });

    tearDownAll(() async {
      OperatorPresenceHeartbeat.stationNameReader = () =>
          Platform.localHostname;
      await releaseCallLoggerTestDatabase();
    });

    test('χωρίς συνδεδεμένο χρήστη δεν γράφεται τίποτα', () async {
      await heartbeat.beatOnce();

      expect(await repository.getAll(), isEmpty);
    });

    test('με συνδεδεμένο χρήστη γράφεται ο σταθμός του', () async {
      CurrentOperator.activate(_operator(7));

      await heartbeat.beatOnce();

      final marks = await repository.getAll();
      expect(marks, hasLength(1));
      expect(marks.single.operatorId, 7);
      expect(marks.single.station, 'ΔΟΚΙΜΗ-01');
    });

    test('χωρίς όνομα σταθμού δεν γράφεται τίποτα', () async {
      // Σε σύστημα που δεν δίνει όνομα υπολογιστή, ένα ίχνος χωρίς σταθμό δεν
      // απαντά σε τίποτα.
      OperatorPresenceHeartbeat.stationNameReader = () => '';
      CurrentOperator.activate(_operator(7));

      await heartbeat.beatOnce();

      expect(await repository.getAll(), isEmpty);
    });

    test('σφάλμα στην ανάγνωση του σταθμού δεν ρίχνει την εφαρμογή', () {
      OperatorPresenceHeartbeat.stationNameReader = () =>
          throw const FileSystemException('το σύστημα δεν απαντά');

      expect(OperatorPresenceHeartbeat.stationName, isEmpty);
    });

    test('η αλλαγή χρήστη γράφει ίχνος χωρίς να το ζητήσει κανείς', () async {
      // Το ουσιώδες συμβόλαιο: ο χτύπος δένεται στην ταυτότητα, οπότε κάθε ροή
      // που αλλάζει χρήστη — εκκίνηση, οθόνη επιλογής, «Αλλαγή χρήστη» — τον
      // ενημερώνει μόνη της. Καμία οθόνη δεν χρειάζεται να θυμάται τίποτα.
      heartbeat.start();

      CurrentOperator.activate(_operator(3));
      await heartbeat.pendingBeat;

      final marks = await repository.getAll();
      expect(marks.single.operatorId, 3);
    });

    test('δεύτερος χρήστης αποκτά δικό του ίχνος, ο πρώτος μένει', () async {
      heartbeat.start();

      CurrentOperator.activate(_operator(3));
      await heartbeat.pendingBeat;
      CurrentOperator.activate(_operator(4));
      await heartbeat.pendingBeat;

      final marks = await repository.getAll();
      expect(marks.map((m) => m.operatorId), containsAll([3, 4]));
    });

    test('μετά το stop, η αλλαγή χρήστη δεν γράφει πια', () async {
      heartbeat.start();
      heartbeat.stop();

      CurrentOperator.activate(_operator(9));
      await heartbeat.pendingBeat;

      expect(await repository.getAll(), isEmpty);
    });
  });
}
