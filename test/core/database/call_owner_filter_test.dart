// Ποιος κατέγραψε την κλήση, και πώς φιλτράρεται το Ιστορικό και η αναφορά
// Lansweeper με βάση αυτό.
//
// Ίδιο συμβόλαιο με τις εκκρεμότητες: η σφραγίδα γράφεται ΜΟΝΟ στη δημιουργία
// (καμία επεξεργασία δεν αλλάζει ποιος σήκωσε το τηλέφωνο), οι παλιές κλήσεις
// μένουν «Χωρίς χρήστη», και το φίλτρο στενεύει με ΚΑΙ πάνω στα υπόλοιπα.
//
//   flutter test test/core/database/call_owner_filter_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/models/owner_filter.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/providers/call_owner_filter_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late CallsRepository repo;
  late Database db;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('call_owner_test_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/call_owner.db');
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

  CallModel sample(String issue) => CallModel(
    callerText: 'Δοκιμαστικός Καλών',
    phoneText: '2345',
    issue: issue,
    status: 'completed',
  );

  Future<int?> ownerOf(int callId) async {
    final rows = await db.query(
      'calls',
      columns: ['created_by_operator_id'],
      where: 'id = ?',
      whereArgs: [callId],
    );
    return rows.single['created_by_operator_id'] as int?;
  }

  group('Ποιος κατέγραψε την κλήση', () {
    test('η δημιουργία σφραγίζεται με τον ενεργό χρήστη', () async {
      final me = activateTestOperator('Βασίλης', id: 11);

      final id = await repo.insertCallOnExecutor(db, sample('Νέα κλήση'));

      expect(await ownerOf(id), me.id);
    });

    test('ο κλώνος χρεώνεται σε όποιον τον ανοίγει, όχι στον αρχικό', () async {
      activateTestOperator('Βασίλης', id: 11);
      final sourceId = await repo.insertCallOnExecutor(db, sample('Αρχική'));

      final vlasis = activateTestOperator('Βλάσης', id: 22);
      final cloneId = await repo.cloneCall(sourceId);

      expect(await ownerOf(sourceId), 11);
      expect(
        await ownerOf(cloneId),
        vlasis.id,
        reason:
            'Ο κλώνος είναι νέο περιστατικό — τον δουλεύει αυτός που τον '
            'άνοιξε τώρα.',
      );
    });

    test('χωρίς αναγνωρισμένο χρήστη μένει κενή, δεν εφευρίσκεται', () async {
      final id = await repo.insertCallOnExecutor(db, sample('Ανώνυμη'));

      expect(await ownerOf(id), isNull);
    });

    test('η επεξεργασία δεν αγγίζει ποτέ τη σφραγίδα', () async {
      final me = activateTestOperator('Βασίλης', id: 11);
      final id = await repo.insertCallOnExecutor(db, sample('Αρχικό θέμα'));

      // Άλλος χρήστης διορθώνει το κείμενο — η κλήση παραμένει του πρώτου.
      activateTestOperator('Βλάσης', id: 22);
      final stored = await repo.getCallById(id);
      await repo.updateCall(
        CallModel(
          id: id,
          callerText: stored!.callerText,
          phoneText: stored.phoneText,
          issue: 'Διορθωμένο θέμα',
          status: stored.status,
          date: stored.date,
          time: stored.time,
        ),
      );

      expect(
        await ownerOf(id),
        me.id,
        reason:
            'Η σφραγίδα ζει έξω από τον κοινό χάρτη εγγραφής — αν μπει μέσα, '
            'κάθε διόρθωση κειμένου θα ξαναβάφτιζε την κλήση.',
      );
    });
  });

  group('Το φίλτρο στο Ιστορικό', () {
    Future<void> seedThreeOwners() async {
      activateTestOperator('Βασίλης', id: 11);
      await repo.insertCallOnExecutor(db, sample('Του Βασίλη'));
      activateTestOperator('Βλάσης', id: 22);
      await repo.insertCallOnExecutor(db, sample('Του Βλάση'));
      resetTestOperator();
      await repo.insertCallOnExecutor(db, sample('Αδέσποτη'));
    }

    Future<List<String>> issuesFor(OwnerFilter owner) async {
      final rows = await repo.getHistoryCalls(owner: owner);
      return rows.map((r) => '${r['issue']}').toList()..sort();
    }

    test(
      '«Όλοι» δεν κρύβει τίποτα — η σημερινή συμπεριφορά μένει ίδια',
      () async {
        await seedThreeOwners();

        expect(await issuesFor(OwnerFilter.everyone), [
          'Αδέσποτη',
          'Του Βασίλη',
          'Του Βλάση',
        ]);
      },
    );

    test('κάθε χρήστης απομονώνεται, και οι αδέσποτες επίσης', () async {
      await seedThreeOwners();

      expect(await issuesFor(const OwnerFilter.byOperator(11)), ['Του Βασίλη']);
      expect(await issuesFor(OwnerFilter.unassigned), ['Αδέσποτη']);
    });

    test('συνδυάζεται με τη λέξη-κλειδί ως ΚΑΙ', () async {
      await seedThreeOwners();

      final rows = await repo.getHistoryCalls(
        keyword: 'βλαση',
        owner: const OwnerFilter.byOperator(11),
      );

      expect(
        rows,
        isEmpty,
        reason:
            'Η αναζήτηση βρίσκει του Βλάση, το φίλτρο δείχνει του Βασίλη — '
            'η τομή τους είναι άδεια.',
      );
    });

    test(
      'οι επιλογές του φίλτρου βγαίνουν από τα πραγματικά δεδομένα',
      () async {
        await seedThreeOwners();

        expect((await repo.getDistinctCallOwnerIds())..sort(), [11, 22]);
        expect(await repo.hasUnassignedCalls(), isTrue);
      },
    );

    test('χωρίς αδέσποτες, η επιλογή τους δεν προσφέρεται', () async {
      activateTestOperator('Βασίλης', id: 11);
      await repo.insertCallOnExecutor(db, sample('Μόνη'));

      expect(await repo.hasUnassignedCalls(), isFalse);
    });
  });

  group('Ο κανόνας της αναφοράς Lansweeper', () {
    test(
      'callMatchesOwner λέει το ίδιο πράγμα με το SQL του Ιστορικού',
      () async {
        activateTestOperator('Βασίλης', id: 11);
        await repo.insertCallOnExecutor(db, sample('Του Βασίλη'));
        resetTestOperator();
        await repo.insertCallOnExecutor(db, sample('Αδέσποτη'));

        for (final owner in <OwnerFilter>[
          OwnerFilter.everyone,
          OwnerFilter.unassigned,
          const OwnerFilter.byOperator(11),
          const OwnerFilter.byOperator(99),
        ]) {
          final sqlIssues = (await repo.getHistoryCalls(
            owner: owner,
          )).map((r) => '${r['issue']}').toSet();

          final allRows = await repo.getHistoryCalls();
          final memoryIssues = {
            for (final r in allRows)
              if (callMatchesOwner(owner, r['created_by_operator_id'] as int?))
                '${r['issue']}',
          };

          expect(
            memoryIssues,
            sqlIssues,
            reason:
                'Η αναφορά φιλτράρει στη μνήμη με το callMatchesOwner και το '
                'Ιστορικό στο SQL — αν αποκλίνουν για το $owner, οι δύο οθόνες '
                'δείχνουν διαφορετική αλήθεια για τις ίδιες κλήσεις.',
          );
        }
      },
    );
  });

  group('Αναβάθμιση v54', () {
    late Database rawDb;

    setUp(() async {
      rawDb = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await rawDb.execute('''
        CREATE TABLE calls (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          issue TEXT,
          is_deleted INTEGER DEFAULT 0
        )
      ''');
    });

    tearDown(() async {
      await rawDb.close();
    });

    test('προσθέτει τη στήλη και δεν πειράζει τις υπάρχουσες', () async {
      await rawDb.insert('calls', {'issue': 'Παλιά'});

      await migrateDatabaseToV54(rawDb);

      final row = (await rawDb.query('calls')).single;
      expect(row['created_by_operator_id'], isNull);
      expect(row['issue'], 'Παλιά');
    });

    test('ξανατρέχει χωρίς παρενέργειες', () async {
      await migrateDatabaseToV54(rawDb);
      await migrateDatabaseToV54(rawDb);

      final info = await rawDb.rawQuery('PRAGMA table_info(calls)');
      final columns = info.map((r) => r['name'] as String).toList();
      expect(columns.where((c) => c == 'created_by_operator_id'), hasLength(1));
    });
  });
}
