// Ποιος καταχώρησε την κλήση στο Lansweeper — η σφραγίδα μπαίνει σε ΕΝΑ σημείο.
//
// Τρεις δρόμοι γράφουν εγγραφή συνδέσμου: η χειροκίνητη σήμανση, η επιτυχής
// αποστολή, και η αποτυχία που πρόλαβε να γεννήσει αριθμό αιτήματος. Αν η
// σφραγίδα έμπαινε στους καλούντες, ο ένας θα την ξεχνούσε — και το όνομα θα
// εμφανιζόταν σε κάποιες κλήσεις και σε άλλες όχι, χωρίς ο χρήστης να μπορεί
// να καταλάβει γιατί.
//
// Γι' αυτό ο έλεγχος διαβάζει **τι γράφτηκε πραγματικά στη βάση**, όχι τι
// υποσχέθηκε ο κώδικας: περνά από κάθε δρόμο και ξαναδιαβάζει τη γραμμή.
//
//   flutter test test/core/database/lansweeper_link_submitted_by_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/services/lansweeper_link_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

void main() {
  group('CallsLansweeperRepository — η σφραγίδα του χρήστη', () {
    late Database db;
    late CallsRepository calls;
    late CallsLansweeperRepository lansweeper;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lansweeper_stamp_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/lansweeper_stamp.db',
      );
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('calls');
      await db.delete('call_external_links');
      await db.delete('audit_log');
      calls = CallsRepository(db);
      lansweeper = CallsLansweeperRepository(db);
      CurrentOperator.activate(
        Operator(id: 7, displayName: 'Βασίλης', createdAt: DateTime(2026)),
      );
    });

    tearDown(CurrentOperator.reset);

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> seedCall() => calls.insertCall(
      CallModel(
        date: '2026-09-04',
        time: '12:21',
        issue: 'Δεν συνδέεται στο Medico ο 3524',
        departmentText: 'Καρδιολογική',
      ),
    );

    /// Το όνομα όπως το ξαναδιαβάζει η οθόνη — από τη βάση, όχι από τη μνήμη.
    Future<String?> submittedByOf(int callId) async {
      final links = await lansweeper.getCallExternalLinks(callId);
      return lansweeperSubmittedByFromMetadata(links.first['metadata']);
    }

    test('η χειροκίνητη σήμανση σφραγίζεται', () async {
      final id = await seedCall();
      await lansweeper.markManualPassed(
        callId: id,
        ticketId: '17824',
        expected: null,
        force: true,
      );
      expect(await submittedByOf(id), 'Βασίλης');
    });

    test('η επιτυχής αποστολή σφραγίζεται', () async {
      final id = await seedCall();
      await lansweeper.markLansweeperSynced(
        callId: id,
        ticketId: '17825',
        provider: 'lansweeper',
      );
      expect(await submittedByOf(id), 'Βασίλης');
    });

    test('η σφραγίδα δεν πατά ό,τι έδωσε ο καλών', () async {
      final id = await seedCall();
      await lansweeper.markLansweeperSynced(
        callId: id,
        ticketId: '17826',
        provider: 'lansweeper',
        metadata: <String, dynamic>{
          'mode': 'api_workflow',
          'warnings': <String>['Ο αιτών δεν βρέθηκε στο Lansweeper'],
        },
      );
      final links = await lansweeper.getCallExternalLinks(id);
      expect(await submittedByOf(id), 'Βασίλης');
      expect(
        lansweeperWarningsFromMetadata(links.first['metadata']),
        <String>['Ο αιτών δεν βρέθηκε στο Lansweeper'],
        reason: greekExpectMsg(
          'Η σφραγίδα μπαίνει ΔΙΠΛΑ στα μεταδεδομένα, δεν τα αντικαθιστά',
        ),
      );
    });

    test('η απευθείας εγγραφή συνδέσμου σφραγίζεται κι αυτή', () async {
      // Ο τρίτος δρόμος: αποστολή που απέτυχε αφού είχε ήδη γεννηθεί αριθμός.
      // Εκεί το όνομα διαβάζεται «ποιος το προσπάθησε» — εξίσου χρήσιμο.
      final id = await seedCall();
      await lansweeper.addExternalLink(
        callId: id,
        externalId: '17827',
        provider: 'lansweeper',
        metadata: <String, dynamic>{'mode': 'api_workflow_failed'},
      );
      expect(await submittedByOf(id), 'Βασίλης');
    });

    test('χωρίς αναγνωρισμένο χρήστη δεν γράφεται σφραγίδα', () async {
      CurrentOperator.reset();
      final id = await seedCall();
      await lansweeper.addExternalLink(
        callId: id,
        externalId: '17828',
        provider: 'lansweeper',
      );
      expect(
        await submittedByOf(id),
        isNull,
        reason: greekExpectMsg(
          'Ό,τι δεν ξέρουμε δεν το γράφουμε — κενή σφραγίδα μοιάζει με απάντηση',
        ),
      );
    });
  });
}
