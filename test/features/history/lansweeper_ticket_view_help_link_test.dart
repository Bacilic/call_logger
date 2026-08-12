// «Έλεγχος συνδέσμου» προβολής ticket: ο αριθμός αιτήματος έρχεται από τη βάση
// (το πιο πρόσφατο υπαρκτό), και μόνο όταν δεν υπάρχει κανένα μπαίνει δείγμα.
//
//   flutter test test/features/history/lansweeper_ticket_view_help_link_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_url_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

const _kTemplate = 'http://10.10.201.22:81/helpdesk/ticket.aspx?tid={tid}';

void main() {
  group('ticketViewUrlForHelpLink', () {
    test('χρησιμοποιεί τον αριθμό αιτήματος που δόθηκε', () {
      final url = LansweeperUrlRules.ticketViewUrlForHelpLink(
        _kTemplate,
        ticketId: '20481',
      );

      expect(url, 'http://10.10.201.22:81/helpdesk/ticket.aspx?tid=20481');
      expect(url, isNot(contains(kSampleLansweeperTicketId)));
    });

    test('χωρίς αριθμό αιτήματος πέφτει στο δείγμα', () {
      final url = LansweeperUrlRules.ticketViewUrlForHelpLink(_kTemplate);

      expect(url, contains('tid=$kSampleLansweeperTicketId'));
    });

    test('κενός αριθμός αιτήματος μετράει σαν να λείπει', () {
      final url = LansweeperUrlRules.ticketViewUrlForHelpLink(
        _kTemplate,
        ticketId: '   ',
      );

      expect(url, contains('tid=$kSampleLansweeperTicketId'));
    });

    test('τιμώνται τα άλλα πρότυπα με τον αριθμό της βάσης', () {
      expect(
        LansweeperUrlRules.ticketViewUrlForHelpLink(
          'http://ls/helpdesk/ticket.aspx?tid=[id_ticket]',
          ticketId: '20481',
        ),
        'http://ls/helpdesk/ticket.aspx?tid=20481',
      );
      expect(
        LansweeperUrlRules.ticketViewUrlForHelpLink(
          'http://ls/helpdesk/ticket.aspx?tid=',
          ticketId: '20481',
        ),
        'http://ls/helpdesk/ticket.aspx?tid=20481',
      );
    });

    test('κενό πεδίο πέφτει στο προεπιλεγμένο πρότυπο, με τον ίδιο αριθμό', () {
      final url = LansweeperUrlRules.ticketViewUrlForHelpLink(
        '',
        ticketId: '20481',
      );

      expect(url, contains('tid=20481'));
      expect(url, startsWith('http://'));
    });
  });

  group('ο αριθμός που τραβιέται από τη βάση', () {
    late Database db;
    late CallsLansweeperRepository repo;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('ticket_help_link_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/help_link.db');
      db = await DatabaseHelper.instance.database;
      repo = CallsLansweeperRepository(db);
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('call_external_links');
      await db.delete('calls');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> insertCall({
      String? ticketId,
      bool isDeleted = false,
    }) {
      return db.insert('calls', {
        'date': '2026-08-12',
        'time': '09:15',
        'issue': 'δοκιμή συνδέσμου',
        'caller_text': 'Δοκιμαστής',
        'phone_text': '2435',
        'status': 'completed',
        'lansweeper_state': ticketId == null ? 'unsent' : 'sent',
        'lansweeper_main_ticket_id': ticketId,
        'search_index': 'δοκιμη συνδεσμου',
        'is_deleted': isDeleted ? 1 : 0,
      });
    }

    test('καμία καταχώρηση -> null, ώστε να μπει το δείγμα', () async {
      await insertCall();

      expect(await repo.maxNumericLansweeperTicketId(), isNull);
    });

    test('επιστρέφει το πιο πρόσφατο (μεγαλύτερο) αίτημα', () async {
      await insertCall(ticketId: '17140');
      await insertCall(ticketId: '20481');
      await insertCall(ticketId: '19003');

      expect(await repo.maxNumericLansweeperTicketId(), 20481);
    });

    test('αγνοεί αίτημα διαγραμμένης κλήσης', () async {
      await insertCall(ticketId: '17140');
      await insertCall(ticketId: '99999', isDeleted: true);

      expect(await repo.maxNumericLansweeperTicketId(), 17140);
    });

    test('βλέπει και το ιστορικό συνδέσεων της κλήσης', () async {
      final callId = await insertCall(ticketId: '17140');
      await db.insert('call_external_links', {
        'call_id': callId,
        'external_id': '20481',
        'provider': 'lansweeper',
        'created_at': '2026-08-12T09:15:00.000',
      });

      expect(await repo.maxNumericLansweeperTicketId(), 20481);
    });

    test('ο σύνδεσμος χτίζεται με τον αριθμό της βάσης, όχι με δείγμα', () async {
      await insertCall(ticketId: '20481');

      final fromDb = await repo.maxNumericLansweeperTicketId();
      final url = LansweeperUrlRules.ticketViewUrlForHelpLink(
        _kTemplate,
        ticketId: fromDb?.toString(),
      );

      expect(url, 'http://10.10.201.22:81/helpdesk/ticket.aspx?tid=20481');
    });
  });
}
