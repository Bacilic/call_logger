// Το εξευγενισμένο κείμενο που φεύγει προς Lansweeper επιστρέφει στην κλήση:
// γράφεται σε όλες τις κλήσεις του ticket, δεν αγγίζει ποτέ το ωμό `issue`, και
// γίνεται αναζητήσιμο στο ίδιο ευρετήριο με όλα τα υπόλοιπα.
//
//   flutter test test/core/database/call_refined_texts_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/features/calls/models/call_refined_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

const _kRawIssue = 'Βλέπει μαυρη οθόνη από το πρωί';
const _kRefinedProblem =
    'Το τμήμα Πρωτόκολλο αναφέρει ότι ο υπολογιστής 5151 εμφανίζει μαύρη οθόνη '
    'από το πρωί.';
const _kSolution =
    'Διευκρινίστηκε ότι η μαύρη οθόνη οφείλεται σε ενεργή συνεδρία VNC. '
    'Πραγματοποιήθηκε αποσύνδεση του χρήστη και η προβολή αποκαταστάθηκε.';

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
      'date': '2026-07-15',
      'time': '13:05',
      'issue': issue,
      'caller_text': 'Μαρίνα Κυνηγάρη',
      'phone_text': '2848',
      'department_text': 'Πρωτόκολλο',
      'equipment_text': '5151',
      'status': 'completed',
      'lansweeper_state': 'unsent',
      'search_index': 'βλεπει μαυρη οθονη απο το πρωι μαρινα κυνηγαρη 2848',
      'is_deleted': 0,
    });
  }

  Future<Map<String, Object?>> readCall(int id) async {
    final rows = await db.query('calls', where: 'id = ?', whereArgs: [id]);
    return rows.single;
  }

  test('το καθαρό κείμενο γράφεται χωρίς να αγγίξει το ωμό «issue»', () async {
    final callId = await insertCall();

    await repo.saveRefinedTexts(
      callIds: [callId],
      problem: _kRefinedProblem,
      solution: _kSolution,
      source: CallRefinedSource.aiEdited,
    );

    final row = await readCall(callId);
    expect(row['issue'], _kRawIssue);
    expect(row['issue_refined'], _kRefinedProblem);
    expect(row['solution'], _kSolution);
    expect(row['refined_source'], CallRefinedSource.aiEdited);
    expect((row['refined_at'] as String?)?.isNotEmpty, isTrue);
  });

  test('όλες οι κλήσεις του ίδιου ticket παίρνουν το κείμενο', () async {
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
      expect(row['issue_refined'], _kRefinedProblem, reason: 'κλήση $id');
      expect(row['solution'], _kSolution, reason: 'κλήση $id');
    }
    // Το ωμό κάθε κλήσης παραμένει το δικό της.
    expect((await readCall(second))['issue'], 'BI forms δεν μπαινει');
  });

  test('άδεια φόρμα δεν σβήνει ό,τι έγραψε προηγούμενη αποστολή', () async {
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
    expect(row['issue_refined'], _kRefinedProblem);
    expect(row['solution'], _kSolution);
  });

  test('η κλήση βρίσκεται από λέξη που υπάρχει μόνο στο καθαρό κείμενο', () async {
    final callId = await insertCall();
    expect(await calls.getHistoryCalls(keyword: 'VNC'), isEmpty);

    await repo.saveRefinedTexts(
      callIds: [callId],
      problem: _kRefinedProblem,
      solution: _kSolution,
      source: CallRefinedSource.ai,
    );

    final found = await calls.getHistoryCalls(keyword: 'VNC');
    expect(found, hasLength(1));
    expect(found.single['id'], callId);
  });

  test('το ωμό κείμενο παραμένει αναζητήσιμο μετά τον εξευγενισμό', () async {
    final callId = await insertCall();

    await repo.saveRefinedTexts(
      callIds: [callId],
      problem: _kRefinedProblem,
      solution: _kSolution,
      source: CallRefinedSource.ai,
    );

    // «μαυρη» χωρίς τόνο, όπως γράφτηκε βιαστικά στο τηλέφωνο.
    final found = await calls.getHistoryCalls(keyword: 'μαυρη');
    expect(found, hasLength(1));
    expect(found.single['id'], callId);
  });

  test('η εγγραφή καταγράφεται στο Ιστορικό ως δική της ενέργεια', () async {
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

  test('η μετάπτωση v41 προσθέτει τις στήλες και ξανατρέχει αζήμια', () async {
    await migrateDatabaseToV41(db);
    await migrateDatabaseToV41(db);

    final info = await db.rawQuery('PRAGMA table_info(calls)');
    final names = info.map((r) => r['name'] as String).toSet();
    expect(
      names,
      containsAll(<String>[
        'issue_refined',
        'solution',
        'refined_source',
        'refined_at',
      ]),
    );
  });
}
