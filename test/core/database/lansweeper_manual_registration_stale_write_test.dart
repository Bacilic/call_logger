// Φρουρός μπαγιάτικης χειροκίνητης καταχώρησης στο Lansweeper.
//
// Το σενάριο των 13:00: δύο άνθρωποι περνούν την ίδια ουρά. Ο συνάδελφος
// καταχωρεί την κλήση με αίτημα #8001. Η δική μου ουρά τη δείχνει ακόμη
// ακαταχώρητη, οπότε η «Σήμανση ως καταχωρημένη» γράφει το δικό μου #8002
// από πάνω — και το #8001 μένει ορφανό στο Lansweeper, χωρίς να το μάθει
// κανείς. Η εφαρμογή δεν μπορεί να σβήσει αιτήματα.
//
//   flutter test test/core/database/lansweeper_manual_registration_stale_write_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/models/lansweeper_sync_state.dart';
import 'package:call_logger/features/history/services/lansweeper_registration_conflict.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('CallsLansweeperRepository — φρουρός χειροκίνητης καταχώρησης', () {
    late Database db;
    late CallsRepository calls;
    late CallsLansweeperRepository lansweeper;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lansweeper_stale_');
      await DatabaseHelper.bindTestDatabaseFile(
        '${dir.path}/lansweeper_stale.db',
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
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    /// Η ουρά της Αναφοράς όπως τη διάβασε η οθόνη μου, και μετά η καταχώρηση
    /// του συναδέλφου από το άλλο μηχάνημα.
    Future<({LansweeperRegistrationBaseline stale, int id})>
    queueReadThenOtherRegisters() async {
      final id = await calls.insertCall(
        CallModel(
          date: '2026-08-25',
          time: '12:40',
          issue: 'Δεν ανοίγει το πρόγραμμα στη Γραμματεία ΤΕΠ',
          status: 'completed',
        ),
      );
      final asMyQueueSawIt = (await calls.getCallById(id))!;
      expect(asMyQueueSawIt.lansweeperState, LansweeperSyncState.unsent);
      final stale = LansweeperRegistrationBaseline.ofCall(asMyQueueSawIt);

      await lansweeper.markManualPassed(
        callId: id,
        ticketId: '8001',
        expected: LansweeperRegistrationBaseline.ofCall(asMyQueueSawIt),
      );

      final afterOther = (await calls.getCallById(id))!;
      expect(afterOther.lansweeperState, LansweeperSyncState.sent);
      expect(afterOther.lansweeperMainTicketId, '8001');
      return (stale: stale, id: id);
    }

    test('η σήμανση δεν σβήνει το αίτημα που καταχώρησε ο άλλος', () async {
      final scenario = await queueReadThenOtherRegisters();

      await expectLater(
        () => lansweeper.markManualPassed(
          callId: scenario.id,
          ticketId: '8002',
          expected: scenario.stale,
        ),
        throwsA(isA<LansweeperRegistrationStaleException>()),
      );

      final stored = (await calls.getCallById(scenario.id))!;
      expect(
        stored.lansweeperMainTicketId,
        '8001',
        reason: 'το αίτημα του συναδέλφου δεν επιτρέπεται να αντικατασταθεί',
      );
    });

    test('η εξαίρεση λέει ποιο αίτημα κινδυνεύει', () async {
      final scenario = await queueReadThenOtherRegisters();

      try {
        await lansweeper.markManualPassed(
          callId: scenario.id,
          ticketId: '8002',
          expected: scenario.stale,
        );
        fail('Έπρεπε να απορριφθεί η μπαγιάτικη καταχώρηση');
      } on LansweeperRegistrationStaleException catch (e) {
        expect(e.conflict.otherRegistered, isTrue);
        expect(e.conflict.freshTicketId, '8001');
        expect(e.conflict.attemptedTicketId, '8002');
        expect(e.conflict.overwriteWarning, contains('8001'));
      }
    });

    test('με force γράφεται η δική μου καταχώρηση', () async {
      final scenario = await queueReadThenOtherRegisters();

      await lansweeper.markManualPassed(
        callId: scenario.id,
        ticketId: '8002',
        expected: scenario.stale,
        force: true,
      );

      final stored = (await calls.getCallById(scenario.id))!;
      expect(stored.lansweeperMainTicketId, '8002');
    });

    test('χωρίς ξένη αλλαγή η σήμανση περνά κανονικά', () async {
      final id = await calls.insertCall(
        CallModel(date: '2026-08-25', time: '12:40', issue: 'αρχικό'),
      );
      final fresh = (await calls.getCallById(id))!;

      await lansweeper.markManualPassed(
        callId: id,
        ticketId: '8003',
        expected: LansweeperRegistrationBaseline.ofCall(fresh),
      );

      final stored = (await calls.getCallById(id))!;
      expect(stored.lansweeperState, LansweeperSyncState.sent);
      expect(stored.lansweeperMainTicketId, '8003');
    });

    test('χωρίς αφετηρία δεν μπλοκάρει (fail-open)', () async {
      final scenario = await queueReadThenOtherRegisters();

      await lansweeper.markManualPassed(
        callId: scenario.id,
        ticketId: '8002',
        expected: null,
      );

      expect(
        (await calls.getCallById(scenario.id))!.lansweeperMainTicketId,
        '8002',
      );
    });

    test('ίδιο αίτημα από τους δύο μας δεν είναι διένεξη', () async {
      final scenario = await queueReadThenOtherRegisters();

      await lansweeper.markManualPassed(
        callId: scenario.id,
        ticketId: '8001',
        expected: scenario.stale,
      );

      expect(
        (await calls.getCallById(scenario.id))!.lansweeperMainTicketId,
        '8001',
      );
    });

    test('η επαναφορά σε ακαταχώρητη δεν σβήνει το ξένο αίτημα', () async {
      final scenario = await queueReadThenOtherRegisters();

      // Η ουρά μου δείχνει την κλήση ακαταχώρητη και χωρίς αίτημα, οπότε η
      // ερώτηση «να κρατηθεί το αίτημα;» δεν εμφανίζεται καν — η επαναφορά
      // πάει κατευθείαν να καθαρίσει αριθμό που δεν ξέρει ότι υπάρχει.
      await expectLater(
        () => lansweeper.updateLansweeperState(
          callId: scenario.id,
          state: LansweeperSyncState.unsent,
          clearTicketId: true,
          expected: scenario.stale,
        ),
        throwsA(isA<LansweeperRegistrationStaleException>()),
      );

      final stored = (await calls.getCallById(scenario.id))!;
      expect(stored.lansweeperMainTicketId, '8001');
      expect(stored.lansweeperState, LansweeperSyncState.sent);
    });

    test('η εξαίρεση πάνω σε ξένη καταχώρηση σταματά και ρωτά', () async {
      final scenario = await queueReadThenOtherRegisters();

      await expectLater(
        () => lansweeper.updateLansweeperState(
          callId: scenario.id,
          state: LansweeperSyncState.excluded,
          expected: scenario.stale,
        ),
        throwsA(isA<LansweeperRegistrationStaleException>()),
      );

      expect(
        (await calls.getCallById(scenario.id))!.lansweeperState,
        LansweeperSyncState.sent,
      );
    });

    test(
      'σήμανση χωρίς αριθμό: δεν αγγίζει το ξένο αίτημα, δεν ρωτά',
      () async {
        final scenario = await queueReadThenOtherRegisters();

        // Η κατάσταση είναι ήδη «καταχωρημένη» και η εγγραφή δεν αγγίζει τον
        // αριθμό: δεν χάνεται τίποτα, οπότε ένας διάλογος εδώ θα ήταν σκέτος
        // θόρυβος πάνω στη ρουτίνα των 13:00.
        await lansweeper.updateLansweeperState(
          callId: scenario.id,
          state: LansweeperSyncState.sent,
          expected: scenario.stale,
        );

        final stored = (await calls.getCallById(scenario.id))!;
        expect(stored.lansweeperMainTicketId, '8001');
        expect(stored.lansweeperState, LansweeperSyncState.sent);
      },
    );
  });
}
