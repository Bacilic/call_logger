// Φρουρός μπαγιάτικης εγγραφής κλήσης. Το βαρύ σενάριο δεν είναι το χαμένο
// κείμενο: η επεξεργασία γράφει ΟΛΟΚΛΗΡΗ τη γραμμή, μαζί με τα πεδία
// Lansweeper — οπότε μια διόρθωση ορθογραφικού επανέφερε στην ουρά κλήση που
// ο συνάδελφος είχε ήδη καταχωρήσει, και το επόμενο πέρασμα άνοιγε ΔΕΥΤΕΡΟ
// αίτημα στο Lansweeper. Εκείνο δεν σβήνεται από την εφαρμογή.
//
//   flutter test test/core/database/calls_repository_stale_write_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/services/call_save_conflict.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('CallsRepository — φρουρός μπαγιάτικης εγγραφής', () {
    late Database db;
    late CallsRepository calls;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('calls_stale_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/calls_stale.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('calls');
      await db.delete('audit_log');
      calls = CallsRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    /// Η κλήση όπως τη διάβασε ο διάλογος επεξεργασίας, και μετά η καταχώρηση
    /// του συναδέλφου στο Lansweeper από άλλο μηχάνημα.
    Future<({CallModel stale, int id})> openedThenOtherRegisters() async {
      final id = await calls.insertCall(
        CallModel(
          date: '2026-08-24',
          time: '13:05',
          issue: 'Δεν τυπώνει ο εκτυπωτής στη Γραμματία',
          status: 'completed',
        ),
      );
      final stale = (await calls.getCallById(id))!;
      expect(stale.lansweeperState, 'unsent');

      await CallsLansweeperRepository(db).markManualPassed(
        callId: id,
        ticketId: '8001',
      );

      final afterOther = (await calls.getCallById(id))!;
      expect(afterOther.lansweeperState, 'sent');
      expect(afterOther.lansweeperMainTicketId, '8001');
      return (stale: stale, id: id);
    }

    CallModel withIssue(CallModel base, String issue) => CallModel(
      id: base.id,
      date: base.date,
      time: base.time,
      callerId: base.callerId,
      equipmentId: base.equipmentId,
      callerText: base.callerText,
      phoneText: base.phoneText,
      departmentText: base.departmentText,
      equipmentText: base.equipmentText,
      issue: issue,
      solution: base.solution,
      category: base.category,
      categoryId: base.categoryId,
      status: base.status,
      duration: base.duration,
      isPriority: base.isPriority,
      lansweeperState: base.lansweeperState,
      lansweeperMainTicketId: base.lansweeperMainTicketId,
      lansweeperLastSyncAt: base.lansweeperLastSyncAt,
      isDeleted: base.isDeleted,
    );

    test('η διόρθωση κειμένου δεν επαναφέρει την κλήση στην ουρά', () async {
      final scenario = await openedThenOtherRegisters();

      await expectLater(
        () => calls.updateCall(
          withIssue(scenario.stale, 'Δεν τυπώνει ο εκτυπωτής στη Γραμματεία'),
          expected: scenario.stale,
        ),
        throwsA(isA<CallStaleException>()),
      );

      final stored = (await calls.getCallById(scenario.id))!;
      expect(
        stored.lansweeperState,
        'sent',
        reason: 'η κλήση δεν επιτρέπεται να ξαναγίνει ακαταχώρητη',
      );
      expect(
        stored.lansweeperMainTicketId,
        '8001',
        reason: 'χωρίς τον αριθμό αιτήματος το επόμενο πέρασμα ανοίγει δεύτερο',
      );
    });

    test('η εξαίρεση λέει τι άλλαξε ο άλλος', () async {
      final scenario = await openedThenOtherRegisters();

      try {
        await calls.updateCall(
          withIssue(scenario.stale, 'διορθωμένο'),
          expected: scenario.stale,
        );
        fail('Έπρεπε να απορριφθεί η μπαγιάτικη εγγραφή');
      } on CallStaleException catch (e) {
        expect(e.conflict.fresh.lansweeperState, 'sent');
        expect(e.conflict.attempted.issue, 'διορθωμένο');
        expect(e.conflict.changedFields, contains('κατάσταση Lansweeper'));
      }
    });

    test('με force γράφεται η δική μου εικόνα', () async {
      final scenario = await openedThenOtherRegisters();

      await calls.updateCall(
        withIssue(scenario.stale, 'διορθωμένο'),
        expected: scenario.stale,
        force: true,
      );

      expect((await calls.getCallById(scenario.id))!.issue, 'διορθωμένο');
    });

    test('χωρίς ξένη αλλαγή η αποθήκευση περνά κανονικά', () async {
      final id = await calls.insertCall(
        CallModel(date: '2026-08-24', time: '13:05', issue: 'αρχικό'),
      );
      final fresh = (await calls.getCallById(id))!;

      await calls.updateCall(
        withIssue(fresh, 'διορθωμένο'),
        expected: fresh,
      );

      expect((await calls.getCallById(id))!.issue, 'διορθωμένο');
    });

    test('χωρίς αφετηρία δεν μπλοκάρει (fail-open)', () async {
      final scenario = await openedThenOtherRegisters();

      await calls.updateCall(
        withIssue(scenario.stale, 'χωρίς αφετηρία'),
        expected: null,
      );

      expect(
        (await calls.getCallById(scenario.id))!.issue,
        'χωρίς αφετηρία',
      );
    });
  });
}
