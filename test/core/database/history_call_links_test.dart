// Π4: το ιστορικό ξέρει ποιες κλήσεις άφησαν «ουρά» — συνδεδεμένη εκκρεμότητα
// ή αίτημα Lansweeper — και μπορεί να φιλτράρει σε αυτές.
//
//   flutter test test/core/database/history_call_links_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late CallsRepository calls;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('history_links_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/links.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('tasks');
    await db.delete('calls');
    calls = CallsRepository(db);
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertCall({
    required String issue,
    String lansweeperState = 'unsent',
    String? ticketId,
  }) {
    return db.insert('calls', {
      'date': '2026-07-15',
      'time': '13:14',
      'issue': issue,
      'status': 'completed',
      'lansweeper_state': lansweeperState,
      'lansweeper_main_ticket_id': ticketId,
      'is_deleted': 0,
    });
  }

  Future<int> insertTask({
    required int callId,
    String title = 'Εκκρεμότητα',
    int isDeleted = 0,
  }) {
    return db.insert('tasks', {
      'call_id': callId,
      'title': title,
      'description': '',
      'status': 'open',
      'is_deleted': isDeleted,
    });
  }

  Map<String, dynamic> rowFor(
    List<Map<String, dynamic>> rows,
    String issue,
  ) => rows.firstWhere((r) => r['issue'] == issue);

  group('ενδείξεις σύνδεσης στη γραμμή ιστορικού', () {
    test('η κλήση με ανοιχτή εκκρεμότητα σημειώνεται, η άλλη όχι', () async {
      final withTask = await insertCall(issue: 'Με εκκρεμότητα');
      await insertCall(issue: 'Σκέτη');
      await insertTask(callId: withTask);

      final rows = await calls.getHistoryCalls();

      expect(rowFor(rows, 'Με εκκρεμότητα')['has_open_task'], 1);
      expect(rowFor(rows, 'Σκέτη')['has_open_task'], 0);
    });

    test('διαγραμμένη εκκρεμότητα δεν μετράει ως ουρά', () async {
      final callId = await insertCall(issue: 'Σβησμένη εκκρεμότητα');
      await insertTask(callId: callId, isDeleted: 1);

      final rows = await calls.getHistoryCalls();

      expect(rowFor(rows, 'Σβησμένη εκκρεμότητα')['has_open_task'], 0);
    });

    test('το αίτημα Lansweeper αναγνωρίζεται από ticket ή από κατάσταση', () async {
      await insertCall(issue: 'Με ticket', ticketId: '7001');
      await insertCall(issue: 'Σταλμένη', lansweeperState: 'sent');
      await insertCall(issue: 'Καθαρή');

      final rows = await calls.getHistoryCalls();

      expect(rowFor(rows, 'Με ticket')['has_lansweeper_ticket'], 1);
      expect(rowFor(rows, 'Σταλμένη')['has_lansweeper_ticket'], 1);
      expect(rowFor(rows, 'Καθαρή')['has_lansweeper_ticket'], 0);
    });
  });

  group('φίλτρα «μόνο με ουρά»', () {
    test('onlyWithTask κρατά μόνο τις κλήσεις με ανοιχτή εκκρεμότητα', () async {
      final withTask = await insertCall(issue: 'Με εκκρεμότητα');
      await insertCall(issue: 'Σκέτη');
      await insertTask(callId: withTask);

      final rows = await calls.getHistoryCalls(onlyWithTask: true);

      expect(rows, hasLength(1));
      expect(rows.single['issue'], 'Με εκκρεμότητα');
    });

    test('onlyWithLansweeper κρατά μόνο τις κλήσεις με αίτημα', () async {
      await insertCall(issue: 'Με ticket', ticketId: '7001');
      await insertCall(issue: 'Καθαρή');

      final rows = await calls.getHistoryCalls(onlyWithLansweeper: true);

      expect(rows, hasLength(1));
      expect(rows.single['issue'], 'Με ticket');
    });

    test('τα δύο φίλτρα μαζί ζητούν ΚΑΙ τα δύο, όχι ένα από τα δύο', () async {
      final both = await insertCall(issue: 'Και τα δύο', ticketId: '7002');
      await insertTask(callId: both);
      final onlyTask = await insertCall(issue: 'Μόνο εκκρεμότητα');
      await insertTask(callId: onlyTask);
      await insertCall(issue: 'Μόνο ticket', ticketId: '7003');

      final rows = await calls.getHistoryCalls(
        onlyWithTask: true,
        onlyWithLansweeper: true,
      );

      expect(rows, hasLength(1));
      expect(rows.single['issue'], 'Και τα δύο');
    });

    test('τα φίλτρα συνδυάζονται με την αναζήτηση κειμένου', () async {
      final matching = await insertCall(issue: 'Εκτυπωτής χαλασμένος');
      await insertTask(callId: matching);
      final otherWithTask = await insertCall(issue: 'Οθόνη σβηστή');
      await insertTask(callId: otherWithTask);

      // Το search_index γεμίζει από τις ροές παραγωγής· εδώ το γράφουμε ρητά
      // ώστε το τεστ να ελέγχει τον συνδυασμό φίλτρων, όχι την ευρετηρίαση.
      await db.update(
        'calls',
        {'search_index': 'εκτυπωτησ χαλασμενοσ'},
        where: 'id = ?',
        whereArgs: [matching],
      );

      final rows = await calls.getHistoryCalls(
        keyword: 'εκτυπωτησ',
        onlyWithTask: true,
      );

      expect(rows, hasLength(1));
      expect(rows.single['issue'], 'Εκτυπωτής χαλασμένος');
    });
  });
}
