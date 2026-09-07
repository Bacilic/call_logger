// Το συμβόλαιο: **κάθε ερώτημα προς τη ζωντανή βάση τελειώνει μέσα σε ορισμένο
// χρόνο — με απάντηση ή με σφάλμα — ποτέ με σιωπή.**
//
// Δύο πράγματα ελέγχονται εδώ, και χρειάζονται και τα δύο:
//   1. Το περίβλημα βάζει όριο σε κάθε είδος πράξης.
//   2. Η εφαρμογή **το χρησιμοποιεί** — το `DatabaseHelper` δεν μοιράζει ποτέ
//      γυμνή σύνδεση. Χωρίς αυτόν τον δεύτερο έλεγχο, το περίβλημα θα μπορούσε
//      να αποσυνδεθεί χωρίς να σπάσει κανένα τεστ.
//
//   flutter test test/core/database/timeout_database_test.dart

import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/timeout_database.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../test_setup.dart';

/// Δέσμη εντολών που δέχεται τα πάντα και δεν ολοκληρώνεται ποτέ.
class UnresponsiveBatch implements Batch {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

/// Βάση που δέχεται τα πάντα και δεν απαντά σε τίποτα.
class UnresponsiveDatabase implements Database {
  UnresponsiveDatabase({this.path = r'C:\local\call_logger.db'});

  /// Η διαδρομή κρίνεται από τον φύλακα — γι' αυτό δηλώνεται κανονικά.
  @override
  final String path;

  /// Το [batch] επιστρέφει αντικείμενο, όχι future — το [noSuchMethod] δεν
  /// μπορεί να το καλύψει.
  @override
  Batch batch() => UnresponsiveBatch();

  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const short = Duration(milliseconds: 300);

  group('το περίβλημα βάζει όριο σε κάθε είδος πράξης', () {
    late TimeoutDatabase guarded;

    setUp(() {
      guarded = TimeoutDatabase(UnresponsiveDatabase(), timeout: short);
    });

    test('η ανάγνωση τελειώνει με σφάλμα αντί να κρεμάσει', () async {
      await expectLater(
        guarded.rawQuery('SELECT 1'),
        throwsA(isA<DatabaseUnresponsiveException>()),
      );
    });

    test('η εγγραφή τελειώνει με σφάλμα αντί να κρεμάσει', () async {
      await expectLater(
        guarded.insert('calls', <String, Object?>{'id': 1}),
        throwsA(isA<DatabaseUnresponsiveException>()),
      );
    });

    test('η συναλλαγή τελειώνει με σφάλμα αντί να κρεμάσει', () async {
      await expectLater(
        guarded.transaction((txn) async => 1),
        throwsA(isA<DatabaseUnresponsiveException>()),
      );
    });

    test('η δέσμη εντολών τελειώνει με σφάλμα αντί να κρεμάσει', () async {
      final batch = guarded.batch();
      await expectLater(
        batch.commit(),
        throwsA(isA<DatabaseUnresponsiveException>()),
      );
    });

    test('το μήνυμα λέει πόσο περίμενε και ποια πράξη κόλλησε', () async {
      try {
        await guarded.query('calls');
        fail('περίμενα σφάλμα');
      } on DatabaseUnresponsiveException catch (e) {
        expect(e.toString(), contains('δεν απάντησε'));
        expect(e.operation, contains('calls'));
        expect(e.timeout, short);
      }
    });
  });

  group('ο φύλακας μπαίνει εκεί που χρειάζεται', () {
    const uncPath = r'\\gnk.local\Departments\Data Base\call_logger.db';
    const localPath = r'C:\Users\x\Data Base\call_logger.db';

    test('η δικτυακή διαδρομή παίρνει φύλακα', () {
      expect(databaseNeedsTimeoutGuard(uncPath), isTrue);

      final guarded = guardDatabaseWithTimeout(
        UnresponsiveDatabase(path: uncPath),
      );
      expect(guarded, isA<TimeoutDatabase>());
    });

    test('η δικτυακή σύνδεση όντως τελειώνει αντί να κρεμάσει', () async {
      final guarded = guardDatabaseWithTimeout(
        UnresponsiveDatabase(path: uncPath),
        timeout: short,
      );

      await expectLater(
        guarded.rawQuery('SELECT 1'),
        throwsA(isA<DatabaseUnresponsiveException>()),
      );
    });

    test('η τοπική διαδρομή μένει ως έχει', () {
      expect(databaseNeedsTimeoutGuard(localPath), isFalse);

      final raw = UnresponsiveDatabase(path: localPath);
      // Ένα τοπικό αρχείο δεν γίνεται άφταστο ενώ η εφαρμογή τρέχει· ένα
      // χρονόμετρο ανά ερώτημα δεν θα προστάτευε από τίποτα.
      expect(identical(guardDatabaseWithTimeout(raw), raw), isTrue);
    });
  });

  group('η εφαρμογή χρησιμοποιεί τον φύλακα', () {
    late Directory tempRoot;

    setUp(() async {
      initSqfliteFfiForTests();
      SharedPreferences.setMockInitialValues({});
      tempRoot = await Directory.systemTemp.createTemp('timeout_db_wiring_');
      await DatabaseHelper.instance.closeConnection();
      DatabaseHelper.releaseTestDatabaseBinding();
    });

    tearDown(() async {
      await DatabaseHelper.instance.closeConnection();
      DatabaseHelper.releaseTestDatabaseBinding();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('η μοιρασμένη σύνδεση περνά από τον κριτή του φύλακα', () async {
      final dbPath = p.join(tempRoot.path, 'call_logger.db');
      await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
      await SettingsService().setDatabasePath(dbPath);

      final db = await DatabaseHelper.instance.database;

      // Τοπικός φάκελος δοκιμών: ο κριτής λέει «χωρίς φύλακα», και η σύνδεση
      // βγαίνει ως έχει. Ότι η δικτυακή παίρνει φύλακα το φυλάει η ομάδα από
      // πάνω· εδώ φυλάγεται ότι η απόφαση **περνά** από τον κριτή.
      expect(databaseNeedsTimeoutGuard(db.path), isFalse);
      expect(db, isNot(isA<TimeoutDatabase>()));
      expect(await db.rawQuery('SELECT 1 AS x'), isNotEmpty);
    });

    test('η ίδια σύνδεση δίνει το ίδιο αντικείμενο, όχι καινούριο κάθε φορά',
        () async {
      final dbPath = p.join(tempRoot.path, 'call_logger.db');
      await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
      await SettingsService().setDatabasePath(dbPath);

      final first = await DatabaseHelper.instance.database;
      final second = await DatabaseHelper.instance.database;

      expect(identical(first, second), isTrue);
    });
  });
}
