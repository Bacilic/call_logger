// Το ιστορικό ξέρει ποιες κλήσεις άφησαν «ουρά» — συνδεδεμένη εκκρεμότητα ή
// κατάσταση Lansweeper — και μπορεί να φιλτράρει σε αυτές.
//
//   flutter test test/core/database/history_call_links_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
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

    test('η γραμμή κουβαλά την κατάσταση Lansweeper και τον αριθμό αιτήματος', () async {
      await insertCall(
        issue: 'Καταχωρημένη',
        lansweeperState: 'sent',
        ticketId: '7001',
      );
      await insertCall(issue: 'Εξαιρεμένη', lansweeperState: 'excluded');
      await insertCall(issue: 'Καθαρή');

      final rows = await calls.getHistoryCalls();

      expect(rowFor(rows, 'Καταχωρημένη')['lansweeper_state'], 'sent');
      expect(rowFor(rows, 'Καταχωρημένη')['lansweeper_ticket_id'], '7001');
      expect(rowFor(rows, 'Εξαιρεμένη')['lansweeper_state'], 'excluded');
      expect(rowFor(rows, 'Καθαρή')['lansweeper_state'], 'unsent');
      expect(rowFor(rows, 'Καθαρή')['lansweeper_ticket_id'], '');
    });

    test('η SQL κανονικοποίηση συμφωνεί με τον κανόνα της Dart', () async {
      // Δύο διατυπώσεις του ίδιου κανόνα: αν αποκλίνουν, η ίδια κλήση πέφτει
      // σε άλλη κατηγορία στο Ιστορικό απ' ό,τι στην Αναφορά.
      //
      // Το `null` λείπει από τη λίστα επίτηδες: η στήλη είναι NOT NULL με
      // DEFAULT 'unsent', οπότε κενή τιμή δεν φτάνει ποτέ στη βάση.
      const rawStates = <String>[
        '',
        '   ',
        'unsent',
        'sent',
        'excluded',
        'failed',
        'unknown_state',
      ];
      for (var i = 0; i < rawStates.length; i++) {
        await db.insert('calls', {
          'date': '2026-07-15',
          'time': '13:14',
          'issue': 'Κατάσταση $i',
          'status': 'completed',
          'lansweeper_state': rawStates[i],
          'is_deleted': 0,
        });
      }

      final rows = await calls.getHistoryCalls();

      for (var i = 0; i < rawStates.length; i++) {
        expect(
          rowFor(rows, 'Κατάσταση $i')['lansweeper_state'],
          LansweeperSyncState.normalize(rawStates[i]),
          reason: 'η ωμή τιμή «${rawStates[i]}» διαβάστηκε αλλιώς στο SQL',
        );
      }
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

    test('το φίλτρο κατάστασης κρατά μόνο τη ζητούμενη κατάσταση', () async {
      await insertCall(issue: 'Καταχωρημένη', lansweeperState: 'sent');
      await insertCall(issue: 'Εξαιρεμένη', lansweeperState: 'excluded');
      await insertCall(issue: 'Ακαταχώρητη');

      final excluded = await calls.getHistoryCalls(
        lansweeperState: LansweeperSyncState.excluded,
      );

      expect(excluded, hasLength(1));
      expect(excluded.single['issue'], 'Εξαιρεμένη');
    });

    test('η εξαιρεμένη ξεχωρίζει από την ακαταχώρητη', () async {
      // Το παλιό δυαδικό φίλτρο δεν μπορούσε να τις χωρίσει: καμία από τις δύο
      // δεν έχει αριθμό αιτήματος, οπότε έπεφταν μαζί έξω.
      await insertCall(issue: 'Εξαιρεμένη', lansweeperState: 'excluded');
      await insertCall(issue: 'Ακαταχώρητη');

      final unsent = await calls.getHistoryCalls(
        lansweeperState: LansweeperSyncState.unsent,
      );

      expect(unsent, hasLength(1));
      expect(unsent.single['issue'], 'Ακαταχώρητη');
    });

    test('κλήση με κενή ή άγνωστη κατάσταση μετράει ως ακαταχώρητη', () async {
      // Κλήση που δεν ταίριαζε πουθενά θα ήταν αόρατη σε κάθε φίλτρο.
      await insertCall(issue: 'Κενή κατάσταση', lansweeperState: '');
      await insertCall(issue: 'Άγνωστη κατάσταση', lansweeperState: 'pending');

      final unsent = await calls.getHistoryCalls(
        lansweeperState: LansweeperSyncState.unsent,
      );

      expect(unsent.map((r) => r['issue']), containsAll(<String>[
        'Κενή κατάσταση',
        'Άγνωστη κατάσταση',
      ]));
    });

    test('κενό φίλτρο κατάστασης δεν περιορίζει τίποτα', () async {
      await insertCall(issue: 'Καταχωρημένη', lansweeperState: 'sent');
      await insertCall(issue: 'Ακαταχώρητη');

      final all = await calls.getHistoryCalls(lansweeperState: '  ');

      expect(all, hasLength(2));
    });

    test('τα δύο φίλτρα μαζί ζητούν ΚΑΙ τα δύο, όχι ένα από τα δύο', () async {
      final both = await insertCall(
        issue: 'Και τα δύο',
        lansweeperState: 'sent',
      );
      await insertTask(callId: both);
      final onlyTask = await insertCall(issue: 'Μόνο εκκρεμότητα');
      await insertTask(callId: onlyTask);
      await insertCall(issue: 'Μόνο καταχώρηση', lansweeperState: 'sent');

      final rows = await calls.getHistoryCalls(
        onlyWithTask: true,
        lansweeperState: LansweeperSyncState.sent,
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
