// Κάθε αλλαγή κατάστασης Lansweeper αφήνει εγγραφή στο Ιστορικό Εφαρμογής.
//
// Παλιότερα καμία από τις τέσσερις ροές δεν κατέγραφε τίποτα: η κλήση φαινόταν
// για πάντα «Μη αποσταλμένη», με μόνη εγγραφή την αρχική δημιουργία της.
//
//   flutter test test/core/database/lansweeper_state_audit_test.dart --timeout 30s

import 'dart:io';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

void main() {
  late Database db;
  late CallsLansweeperRepository repo;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('lansweeper_audit_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/audit.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
    await db.delete('call_external_links');
    await db.delete('calls');
    repo = CallsLansweeperRepository(db);
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertCall() async {
    return db.insert('calls', {
      'date': '2026-07-15',
      'time': '13:14',
      'caller_text': 'Άγνωστος',
      'phone_text': '2360',
      'department_text': 'Ορθοπεδική',
      'equipment_text': '2860',
      'status': 'completed',
      'duration': 101,
      'lansweeper_state': 'unsent',
      'is_deleted': 0,
    });
  }

  Future<List<Map<String, Object?>>> auditRows() =>
      db.query('audit_log', orderBy: 'id ASC');

  test('η αυτόματη καταχώρηση γράφεται στο ιστορικό με τον αριθμό ticket', () async {
    final callId = await insertCall();

    await repo.markLansweeperSynced(
      callId: callId,
      ticketId: '17438',
      provider: 'lansweeper',
    );

    final rows = await auditRows();
    expect(
      rows,
      hasLength(1),
      reason: greekExpectMsg(
        'Χωρίς εγγραφή, η κλήση φαίνεται για πάντα ως μη απεσταλμένη',
      ),
    );
    expect(rows.single['action'], 'ΚΑΤΑΧΩΡΗΣΗ ΣΤΟ LANSWEEPER');
    expect(rows.single['entity_id'], callId);
    expect(
      rows.single['new_values_json'].toString(),
      contains('17438'),
      reason: greekExpectMsg(
        'Ο αριθμός ticket είναι το αποτέλεσμα της ενέργειας — πρέπει να φαίνεται',
      ),
    );
  });

  test('η χειροκίνητη σήμανση ξεχωρίζει από την αυτόματη', () async {
    final callId = await insertCall();

    await repo.markManualPassed(
      callId: callId,
      ticketId: '17438',
      comment: 'Καταχωρήθηκε τηλεφωνικά',
    );

    final rows = await auditRows();
    expect(rows, hasLength(1));
    expect(rows.single['action'], 'ΧΕΙΡΟΚΙΝΗΤΗ ΚΑΤΑΧΩΡΗΣΗ ΣΤΟ LANSWEEPER');
    expect(
      rows.single['new_values_json'].toString(),
      contains('Καταχωρήθηκε τηλεφωνικά'),
      reason: greekExpectMsg(
        'Η αιτιολογία της χειροκίνητης σήμανσης είναι μέρος του γεγονότος',
      ),
    );
  });

  test('η απόσυρση καταγράφεται ως δική της ενέργεια', () async {
    final callId = await insertCall();
    await repo.markLansweeperSynced(
      callId: callId,
      ticketId: '17438',
      provider: 'lansweeper',
    );

    await repo.updateLansweeperState(
      callId: callId,
      state: 'unsent',
      clearTicketId: true,
    );

    final rows = await auditRows();
    expect(rows, hasLength(2));
    expect(rows.last['action'], 'ΑΠΟΣΥΡΣΗ ΑΠΟ LANSWEEPER');
    expect(
      rows.last['old_values_json'].toString(),
      contains('17438'),
      reason: greekExpectMsg(
        'Η προηγούμενη τιμή δείχνει ποιο ticket αποσύρθηκε',
      ),
    );
  });

  test('η αλλαγή αριθμού ticket καταγράφεται', () async {
    final callId = await insertCall();
    await repo.markLansweeperSynced(
      callId: callId,
      ticketId: '17438',
      provider: 'lansweeper',
    );

    await repo.setLansweeperMainTicket(callId: callId, ticketId: '17999');

    final rows = await auditRows();
    expect(rows, hasLength(2));
    expect(rows.last['action'], 'ΑΛΛΑΓΗ TICKET LANSWEEPER');
    expect(rows.last['old_values_json'].toString(), contains('17438'));
    expect(rows.last['new_values_json'].toString(), contains('17999'));
  });

  test('επανάληψη της ίδιας τιμής ΔΕΝ γεμίζει το ιστορικό', () async {
    final callId = await insertCall();
    await repo.markLansweeperSynced(
      callId: callId,
      ticketId: '17438',
      provider: 'lansweeper',
    );

    await repo.setLansweeperMainTicket(callId: callId, ticketId: '17438');

    expect(
      await auditRows(),
      hasLength(1),
      reason: greekExpectMsg(
        'Εγγραφή που δεν λέει καμία αλλαγή είναι θόρυβος στο ιστορικό',
      ),
    );
  });

  group('ονομασία ενέργειας ανά κατάσταση', () {
    test('κάθε κατάσταση έχει δική της ενέργεια', () {
      expect(lansweeperAuditAction('sent'), 'ΚΑΤΑΧΩΡΗΣΗ ΣΤΟ LANSWEEPER');
      expect(lansweeperAuditAction('unsent'), 'ΑΠΟΣΥΡΣΗ ΑΠΟ LANSWEEPER');
      expect(lansweeperAuditAction('excluded'), 'ΕΞΑΙΡΕΣΗ ΑΠΟ LANSWEEPER');
      expect(
        lansweeperAuditAction('failed'),
        'ΑΠΟΤΥΧΙΑ ΚΑΤΑΧΩΡΗΣΗΣ LANSWEEPER',
      );
    });

    test('άγνωστη κατάσταση δεν σπάει — γενική ενέργεια', () {
      expect(
        lansweeperAuditAction('κάτι_νέο'),
        'ΑΛΛΑΓΗ ΚΑΤΑΣΤΑΣΗΣ LANSWEEPER',
      );
    });
  });
}
