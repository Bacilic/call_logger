// Ένα ίχνος παρουσίας κοστίζει ΜΙΑ συναλλαγή, όχι δύο.
//
// Σε βάση πάνω από κοινόχρηστο φάκελο το κόστος μιας εγγραφής είναι **ανά
// συναλλαγή**, όχι ανά δεδομένο: κάθε συναλλαγή δημιουργεί, συγχρονίζει και
// σβήνει το αρχείο ημερολογίου. Μετρημένο στην πραγματική βάση 21/09/2026:
// μία συναλλαγή 2,4 δευτ. — δύο διαδοχικές 4,9 δευτ., ενώ οι ίδιες δύο εντολές
// μέσα σε μία συναλλαγή έμειναν στα 2,4. Ο χτύπος παρουσίας τρέχει κάθε λεπτό,
// οπότε η διαφορά είναι μόνιμη διαμάχη για το κλείδωμα της κοινής βάσης.
//
//   flutter test test/core/database/presence_touch_is_one_transaction_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/operator_presence_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Σύνδεση που μετρά πόσες φορές την πλησίασε ο κώδικας — και πώς.
///
/// Μετρά **συναλλαγές** και **εγγραφές εκτός συναλλαγής**, γιατί ακριβώς αυτά
/// πληρώνονται στο δίκτυο. Ό,τι δεν προωθείται ρητά χτυπά, ώστε μια μελλοντική
/// αλλαγή να μην περνά απαρατήρητη μέσα από το [noSuchMethod].
class _CountingDatabase implements Database {
  _CountingDatabase(this._inner);

  final Database _inner;

  int transactions = 0;
  int writesOutsideTransaction = 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) {
    transactions++;
    return _inner.transaction(action, exclusive: exclusive);
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    writesOutsideTransaction++;
    return _inner.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    writesOutsideTransaction++;
    return _inner.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Το τεστ δεν προωθεί ${invocation.memberName}. Αν ο κώδικας το χρειάζεται '
    'τώρα, πρόσθεσέ το ρητά — και μέτρησέ το αν είναι εγγραφή.',
  );
}

void main() {
  group('Ο χτύπος παρουσίας πληρώνει μία συναλλαγή', () {
    late Database db;
    late _CountingDatabase counting;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 50);
      await migrateDatabaseToV52(db);
      await migrateDatabaseToV60(db);
      counting = _CountingDatabase(db);
    });

    tearDown(() async => db.close());

    test('το ίχνος και η παράδοση γράφονται μαζί, σε μία συναλλαγή', () async {
      await OperatorPresenceRepository(counting).touch(
        operatorId: 7,
        station: 'PC3569',
        instance: r'E:\call_logger\call_logger.exe|dev',
        appVersion: '0.57.0',
        at: DateTime(2026, 9, 21, 10, 20),
      );

      expect(
        counting.transactions,
        1,
        reason:
            'Κάθε συναλλαγή στο δίκτυο κοστίζει ~2,4 δευτερόλεπτα. Δύο '
            'ξεχωριστές διπλασιάζουν τον χρόνο που η κοινή βάση μένει '
            'κλειδωμένη, κάθε λεπτό, από κάθε σταθμό.',
      );
      expect(
        counting.writesOutsideTransaction,
        0,
        reason:
            'Μια εγγραφή έξω από τη συναλλαγή είναι δεύτερο ημερολόγιο στο '
            'δίκτυο — ακριβώς το κόστος που μετράμε.',
      );
    });

    test(
      'το ίχνος χωρίς ταυτότητα αντιγράφου μένει επίσης μία συναλλαγή',
      () async {
        await OperatorPresenceRepository(counting).touch(
          operatorId: 7,
          station: 'PC3569',
          at: DateTime(2026, 9, 21, 10, 20),
        );

        expect(counting.transactions, 1);
        expect(counting.writesOutsideTransaction, 0);
      },
    );

    test('χωρίς παράδοση, ο προηγούμενος κρατά το αντίγραφό του', () async {
      const sameInstance = r'E:\call_logger\call_logger.exe|dev';
      final repository = OperatorPresenceRepository(counting);

      await repository.touch(
        operatorId: 7,
        station: 'PC3569',
        instance: sameInstance,
        at: DateTime(2026, 9, 21, 10, 20),
      );
      await repository.touch(
        operatorId: 9,
        station: 'PC3569',
        instance: sameInstance,
        at: DateTime(2026, 9, 21, 10, 21),
        handOverOtherOperators: false,
      );

      final rows = await db.query(
        OperatorPresenceRepository.tableName,
        where: 'operator_id = ?',
        whereArgs: [7],
      );

      expect(
        rows.single['instance'],
        sameInstance,
        reason:
            'Ο περιοδικός χτύπος δεν ζητά παράδοση — δεν έχει λόγο να πειράξει '
            'το ίχνος κανενός άλλου.',
      );
    });

    test('με παράδοση, ο προηγούμενος αφήνει το αντίγραφο', () async {
      const sameInstance = r'E:\call_logger\call_logger.exe|dev';
      final repository = OperatorPresenceRepository(counting);

      await repository.touch(
        operatorId: 7,
        station: 'PC3569',
        instance: sameInstance,
        at: DateTime(2026, 9, 21, 10, 20),
      );
      await repository.touch(
        operatorId: 9,
        station: 'PC3569',
        instance: sameInstance,
        at: DateTime(2026, 9, 21, 10, 21),
      );

      final rows = await db.query(
        OperatorPresenceRepository.tableName,
        where: 'operator_id = ?',
        whereArgs: [7],
      );

      expect(
        rows.single['instance'],
        isNull,
        reason:
            'Ένα αντίγραφο έχει έναν χρήστη τη φορά — η αλλαγή χρήστη παραδίδει.',
      );
    });
  });
}
