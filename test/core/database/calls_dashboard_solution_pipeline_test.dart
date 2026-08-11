// Η φόρμα της Αναφοράς Lansweeper υπόσχεται ότι φορτώνει την ήδη γραμμένη
// Λύση από την κλήση — άρα η πηγή δεδομένων της αναφοράς (getDashboardCalls)
// οφείλει να τη φέρνει από τη βάση.
//
// Το σφάλμα που αναπαράγεται εδώ: η προσυμπλήρωση της φόρμας διορθώθηκε και
// δοκιμάστηκε με χειροποίητα CallModel (τεστ που φύλαγε αντίγραφο), αλλά το
// πραγματικό ερώτημα SQL διάλεγε στήλες με το χέρι και ΔΕΝ έφερνε τη
// `solution` — οπότε η λύση δεν έφτανε ποτέ στη φόρμα, όσο σωστή κι αν ήταν
// η προσυμπλήρωση. Αυτό το τεστ δένει ολόκληρη τη διαδρομή:
// βάση → ερώτημα → μοντέλο.
//
//   flutter test test/core/database/calls_dashboard_solution_pipeline_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_dashboard_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/dashboard_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Database db;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dash_solution_');
    final dbPath = p.join(tempDir.path, 'calls.db');
    await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
    db = await openDatabase(dbPath, singleInstance: false);
  });

  tearDown(() async {
    if (db.isOpen) {
      await db.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'η λύση (και τα συνοδευτικά της) φτάνουν από τη βάση στις κλήσεις '
    'της αναφοράς',
    () async {
      await CallsRepository(db).insertCall(
        CallModel(
          date: '2026-08-11',
          time: '14:24:00',
          phoneText: '2531',
          issue: 'docutracks μη έμπιστη σελίδα',
          solution: 'ενημέρωση το chrome ότι είναι έγκυρη σελίδα',
          refinedSource: 'manual',
          refinedAt: '2026-08-11T14:24:00',
          status: 'completed',
        ),
      );

      final calls = await CallsDashboardRepository(
        db,
      ).getDashboardCalls(const DashboardFilterModel());

      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.issue, 'docutracks μη έμπιστη σελίδα');
      expect(
        call.solution,
        'ενημέρωση το chrome ότι είναι έγκυρη σελίδα',
        reason:
            'Η Λύση της κλήσης πρέπει να φτάνει στην Αναφορά Lansweeper — '
            'χωρίς αυτήν, η προσυμπλήρωση της φόρμας δεν έχει τι να φορτώσει',
      );
      expect(call.refinedSource, 'manual');
      expect(call.refinedAt, '2026-08-11T14:24:00');
    },
  );
}
