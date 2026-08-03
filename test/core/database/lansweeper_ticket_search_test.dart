// Δ16: η κλήση βρίσκεται από τον αριθμό ticket Lansweeper στην αναζήτηση
// Ιστορικού — το ticket μπαίνει στο search_index και κάθε ροή που το αλλάζει
// ξαναχτίζει το ευρετήριο στην ίδια συναλλαγή.
//
//   flutter test test/core/database/lansweeper_ticket_search_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late CallsLansweeperRepository repo;
  late CallsRepository calls;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('lansweeper_ticket_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/ticket.db');
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

  Future<int> insertCall({String issue = 'Δεν ανοίγει ο υπολογιστής'}) async {
    return db.insert('calls', {
      'date': '2026-07-15',
      'time': '13:14',
      'issue': issue,
      'caller_text': 'Ψαρρά Βαρβάρα',
      'phone_text': '2534',
      'department_text': 'Γραμματεία ΤΕΠ',
      'status': 'completed',
      'lansweeper_state': 'unsent',
      'search_index': 'δεν ανοιγει ο υπολογιστησ ψαρρα βαρβαρα 2534',
      'is_deleted': 0,
    });
  }

  Future<List<Map<String, dynamic>>> searchByTicket(String ticket) {
    return calls.getHistoryCalls(keyword: ticket);
  }

  test('μετά την αυτόματη καταχώρηση η κλήση βρίσκεται από το ticket', () async {
    final callId = await insertCall();

    await repo.markLansweeperSynced(
      callId: callId,
      ticketId: '17438',
      provider: 'lansweeper',
    );

    final found = await searchByTicket('17438');
    expect(found, hasLength(1));
    expect(found.single['id'], callId);
  });

  test('μετά τη χειροκίνητη σήμανση η κλήση βρίσκεται από το ticket', () async {
    final callId = await insertCall();

    await repo.markManualPassed(callId: callId, ticketId: '20991');

    final found = await searchByTicket('20991');
    expect(found, hasLength(1));
    expect(found.single['id'], callId);
  });

  test('αλλαγή κύριου ticket: βρίσκεται από το νέο, όχι από το παλιό', () async {
    final callId = await insertCall();
    await repo.markLansweeperSynced(
      callId: callId,
      ticketId: '17438',
      provider: 'lansweeper',
    );

    await repo.setLansweeperMainTicket(callId: callId, ticketId: '18001');

    expect(await searchByTicket('18001'), hasLength(1));
    expect(await searchByTicket('17438'), isEmpty);
  });

  test('η μετάπτωση v37 κάνει αναζητήσιμα τα ήδη περασμένα tickets', () async {
    // Κλήση με ticket αλλά ΜΠΑΓΙΑΤΙΚΟ ευρετήριο (όπως άφηναν οι παλιές ροές).
    final callId = await insertCall();
    await db.update(
      'calls',
      {'lansweeper_state': 'sent', 'lansweeper_main_ticket_id': '15005'},
      where: 'id = ?',
      whereArgs: [callId],
    );
    expect(await searchByTicket('15005'), isEmpty);

    await migrateDatabaseToV37(db);

    final found = await searchByTicket('15005');
    expect(found, hasLength(1));
    expect(found.single['id'], callId);
  });
}
