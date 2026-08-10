// Το νέο συμβόλαιο της Περιγραφής κλήσης: κάθε κλήση έχει ΕΝΑ κείμενο (`issue`).
// Η φόρμα Lansweeper το ΑΝΤΙΚΑΘΙΣΤΑ με το καθαρό κείμενο του ticket — και στις
// δύο εξόδους — κρατώντας ίχνος προέλευσης/χρόνου. Το πρόχειρο που γράφτηκε στο
// τηλέφωνο χάνεται οριστικά: συνειδητή απόφαση, όχι παράλειψη (10/08/2026).
//
//   flutter test test/core/database/call_refined_texts_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/call_refined_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

const _kRawIssue = 'δεν εκτυπωνει η μπαρκοτιερα';
const _kRefinedProblem =
    'Το τμήμα Ουρολογική αναφέρει ότι ο εκτυπωτής ετικετών στο PC2129 δεν '
    'πραγματοποιεί εκτυπώσεις.';
const _kSolution =
    'Πραγματοποιήθηκε επανεκκίνηση των οδηγών εκτύπωσης μέσα από το περιβάλλον '
    'της εφαρμογής Medico και η διαδικασία εκτύπωσης αποκαταστάθηκε.';

void main() {
  late Database db;
  late CallsLansweeperRepository repo;
  late CallsRepository calls;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('call_refined_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/refined.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('call_external_links');
    await db.delete('calls');
    repo = CallsLansweeperRepository(db);
    calls = CallsRepository(db);
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertCall({String issue = _kRawIssue}) {
    return db.insert('calls', {
      'date': '2026-08-10',
      'time': '08:14',
      'issue': issue,
      'caller_text': 'Μαρίνα Κυνηγάρη',
      'phone_text': '2435',
      'department_text': 'Ουρολογική',
      'equipment_text': '2129',
      'status': 'completed',
      'lansweeper_state': 'unsent',
      // Το ευρετήριο κάθε κλήσης χτίζεται από το ΔΙΚΟ της κείμενο — καρφωτή
      // κοινή τιμή θα έκανε κάθε κλήση να βρίσκεται από λέξεις άλλης.
      'search_index': SearchTextNormalizer.normalizeForSearch(
        '$issue Μαρίνα Κυνηγάρη 2435',
      ),
      'is_deleted': 0,
    });
  }

  Future<Map<String, Object?>> readCall(int id) async {
    final rows = await db.query('calls', where: 'id = ?', whereArgs: [id]);
    return rows.single;
  }

  test('η καταχώρηση ΑΝΤΙΚΑΘΙΣΤΑ την Περιγραφή με το κείμενο του ticket', () async {
    final callId = await insertCall();

    await repo.saveRefinedTexts(
      callIds: [callId],
      problem: _kRefinedProblem,
      solution: _kSolution,
      source: CallRefinedSource.aiEdited,
    );

    final row = await readCall(callId);
    expect(row['issue'], _kRefinedProblem);
    expect(row['solution'], _kSolution);
    expect(row['refined_source'], CallRefinedSource.aiEdited);
    expect((row['refined_at'] as String?)?.isNotEmpty, isTrue);
  });

  test('όλες οι κλήσεις του ίδιου ticket παίρνουν το ίδιο κείμενο', () async {
    final first = await insertCall();
    final second = await insertCall(issue: 'BI forms δεν μπαινει');
    final third = await insertCall(issue: 'Δεν έβλεπε τα εικονίδια');

    await repo.saveRefinedTexts(
      callIds: [first, second, third],
      problem: _kRefinedProblem,
      solution: _kSolution,
      source: CallRefinedSource.ai,
    );

    for (final id in [first, second, third]) {
      final row = await readCall(id);
      expect(row['issue'], _kRefinedProblem, reason: 'κλήση $id');
      expect(row['solution'], _kSolution, reason: 'κλήση $id');
    }
  });

  test('άδεια φόρμα δεν σβήνει ούτε Περιγραφή ούτε λύση', () async {
    final callId = await insertCall();
    await repo.saveRefinedTexts(
      callIds: [callId],
      problem: _kRefinedProblem,
      solution: _kSolution,
      source: CallRefinedSource.ai,
    );

    await repo.saveRefinedTexts(
      callIds: [callId],
      problem: '   ',
      solution: '',
      source: CallRefinedSource.manual,
    );

    final row = await readCall(callId);
    expect(row['issue'], _kRefinedProblem);
    expect(row['solution'], _kSolution);
  });

  test('μόνο λύση χωρίς πρόβλημα δεν αγγίζει την Περιγραφή', () async {
    final callId = await insertCall();

    await repo.saveRefinedTexts(
      callIds: [callId],
      problem: '',
      solution: _kSolution,
      source: CallRefinedSource.manual,
    );

    final row = await readCall(callId);
    expect(row['issue'], _kRawIssue);
    expect(row['solution'], _kSolution);
  });

  test('η κλήση βρίσκεται από το νέο κείμενο· το πρόχειρο παύει να τη '
      'βρίσκει', () async {
    final callId = await insertCall();
    // Το ευρετήριο είναι κανονικοποιημένο (πεζά, άτονα)· το UI κανονικοποιεί
    // το ερώτημα πριν φτάσει εδώ, οπότε το τεστ δίνει ήδη κανονική μορφή.
    expect(await calls.getHistoryCalls(keyword: 'ετικετων'), isEmpty);

    await repo.saveRefinedTexts(
      callIds: [callId],
      problem: _kRefinedProblem,
      solution: _kSolution,
      source: CallRefinedSource.ai,
    );

    final found = await calls.getHistoryCalls(keyword: 'ετικετων');
    expect(found, hasLength(1));
    expect(found.single['id'], callId);
    // Το πρόχειρο αντικαταστάθηκε — η παλιά λέξη δεν υπάρχει πια πουθενά.
    expect(await calls.getHistoryCalls(keyword: 'μπαρκοτιερα'), isEmpty);
  });

  test('η αντικατάσταση καταγράφεται στο Ιστορικό ως αλλαγή του θέματος', () async {
    final callId = await insertCall();

    await repo.saveRefinedTexts(
      callIds: [callId],
      problem: _kRefinedProblem,
      solution: _kSolution,
      source: CallRefinedSource.ai,
    );

    final logs = await db.query(
      'audit_log',
      where: 'action = ?',
      whereArgs: ['ΚΑΘΑΡΟ ΚΕΙΜΕΝΟ ΚΛΗΣΗΣ'],
    );
    expect(logs, hasLength(1));
    expect(logs.single['entity_id'], callId);
    expect(logs.single['old_values_json'], contains(_kRawIssue));
    expect(logs.single['new_values_json'], contains('εκτυπώσεις'));
  });

  test('επανάληψη με ίδιο κείμενο δεν γεμίζει το Ιστορικό', () async {
    final callId = await insertCall();
    for (var i = 0; i < 3; i++) {
      await repo.saveRefinedTexts(
        callIds: [callId],
        problem: _kRefinedProblem,
        solution: _kSolution,
        source: CallRefinedSource.ai,
      );
    }

    final logs = await db.query(
      'audit_log',
      where: 'action = ?',
      whereArgs: ['ΚΑΘΑΡΟ ΚΕΙΜΕΝΟ ΚΛΗΣΗΣ'],
    );
    expect(logs, hasLength(1));
  });

  group('μετάπτωση v43', () {
    Future<void> simulateV42Column() async {
      final info = await db.rawQuery('PRAGMA table_info(calls)');
      final names = info.map((r) => r['name'] as String).toSet();
      if (!names.contains('issue_refined')) {
        await db.execute('ALTER TABLE calls ADD COLUMN issue_refined TEXT');
      }
    }

    Future<Set<String>> callColumns() async {
      final info = await db.rawQuery('PRAGMA table_info(calls)');
      return info.map((r) => r['name'] as String).toSet();
    }

    test('το καθαρό κείμενο κερδίζει, η στήλη πέφτει, το ευρετήριο '
        'ξαναχτίζεται', () async {
      await simulateV42Column();
      final refined = await insertCall();
      final plain = await insertCall(issue: 'Δεν στέλνει email');
      await db.update(
        'calls',
        {'issue_refined': _kRefinedProblem},
        where: 'id = ?',
        whereArgs: [refined],
      );

      await migrateDatabaseToV43(db);

      expect(await callColumns(), isNot(contains('issue_refined')));
      expect((await readCall(refined))['issue'], _kRefinedProblem);
      // Κλήση χωρίς καθαρό κείμενο: η Περιγραφή της μένει όπως ήταν.
      expect((await readCall(plain))['issue'], 'Δεν στέλνει email');
      // Το ευρετήριο δείχνει το νέο κείμενο, όχι το πρόχειρο.
      final found = await calls.getHistoryCalls(keyword: 'ετικετων');
      expect(found, hasLength(1));
      expect(found.single['id'], refined);
      expect(await calls.getHistoryCalls(keyword: 'μπαρκοτιερα'), isEmpty);
    });

    test('ξανατρέχει αζήμια σε βάση που έχει ήδη μεταφερθεί', () async {
      await simulateV42Column();
      await migrateDatabaseToV43(db);

      await migrateDatabaseToV43(db);

      expect(await callColumns(), isNot(contains('issue_refined')));
    });
  });
}
