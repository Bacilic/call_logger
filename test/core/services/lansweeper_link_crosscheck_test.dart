// Ο αμφίδρομος έλεγχος δεσμού: κρατά ήδη αίτημα η άλλη άκρη;
// Και οι δύο κατευθύνσεις περνούν από την ίδια υπηρεσία, ώστε να μην μπορούν
// να απαντήσουν διαφορετικά.
//
//   flutter test test/core/services/lansweeper_link_crosscheck_test.dart

import 'dart:io';

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_lansweeper_repository.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/core/services/lansweeper_link_crosscheck.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('LansweeperLinkCrosscheck', () {
    late LansweeperLinkCrosscheck crosscheck;
    late TasksLansweeperRepository lansweeperRepo;
    late TasksRepository tasksRepo;
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('link_crosscheck_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/crosscheck.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('tasks');
      await db.delete('calls');
      lansweeperRepo = TasksLansweeperRepository(db);
      crosscheck = LansweeperLinkCrosscheck(
        calls: CallsLansweeperRepository(db),
        tasks: lansweeperRepo,
      );
      tasksRepo = TasksRepository();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<int> newCall({String? ticketId}) => db.insert('calls', {
      'issue': 'Δεν τυπώνει',
      'lansweeper_main_ticket_id': ?ticketId,
      if (ticketId != null) 'lansweeper_state': 'sent',
    });

    Future<int> newTask({int? callId, String title = 'Δεν τυπώνει'}) {
      return tasksRepo.createTask(
        Task(
          callId: callId,
          title: title,
          dueDate: DateTime.now().toIso8601String(),
          status: 'open',
        ),
      );
    }

    group('στέλνω εκκρεμότητα — έχει αίτημα η κλήση της;', () {
      test('ναι, και το λέει με τον αριθμό του', () async {
        final callId = await newCall(ticketId: '4821');

        final finding = await crosscheck.forTask(linkedCallId: callId);

        expect(finding, isNotNull);
        expect(finding!.side, LansweeperLinkSide.call);
        expect(finding.ticketId, '4821');
        expect(finding.entityId, callId);
        expect(finding.label, 'την κλήση #$callId');
      });

      test('εκκρεμότητα χωρίς δεσμό προχωρά ελεύθερα', () async {
        expect(await crosscheck.forTask(linkedCallId: null), isNull);
      });

      test('κλήση που δεν στάλθηκε ποτέ δεν σταματά τίποτα', () async {
        final callId = await newCall();

        expect(await crosscheck.forTask(linkedCallId: callId), isNull);
      });

      test('κλήση που έσβησε δεν σταματά τίποτα', () async {
        expect(await crosscheck.forTask(linkedCallId: 99999), isNull);
      });
    });

    group('στέλνω κλήση — έχει αίτημα κάποια εκκρεμότητά της;', () {
      test('ναι, και την ονομάζει με τον τίτλο της', () async {
        final callId = await newCall();
        final taskId = await newTask(
          callId: callId,
          title: 'Αλλαγή καλωδίου στον αξονικό',
        );
        await lansweeperRepo.markSubmitted(taskId: taskId, ticketId: '4821');

        final finding = await crosscheck.forCall(callId: callId);

        expect(finding, isNotNull);
        expect(finding!.side, LansweeperLinkSide.task);
        expect(finding.ticketId, '4821');
        expect(finding.entityId, taskId);
        expect(finding.label, 'την εκκρεμότητα «Αλλαγή καλωδίου στον αξονικό»');
      });

      test('εκκρεμότητα χωρίς αίτημα δεν σταματά τίποτα', () async {
        final callId = await newCall();
        await newTask(callId: callId);

        expect(await crosscheck.forCall(callId: callId), isNull);
      });

      test('κλήση χωρίς εκκρεμότητες προχωρά ελεύθερα', () async {
        final callId = await newCall();

        expect(await crosscheck.forCall(callId: callId), isNull);
      });

      test('διαγραμμένη εκκρεμότητα δεν σταματά τίποτα', () async {
        final callId = await newCall();
        final taskId = await newTask(callId: callId);
        await lansweeperRepo.markSubmitted(taskId: taskId, ticketId: '4821');
        await tasksRepo.deleteTask(taskId);

        expect(await crosscheck.forCall(callId: callId), isNull);
      });
    });

    test('οι δύο κατευθύνσεις βλέπουν τον ΙΔΙΟ δεσμό', () async {
      // Η κλήση έχει αίτημα ΚΑΙ η εκκρεμότητά της έχει άλλο: όποια πλευρά κι
      // αν ρωτήσει, βρίσκει την άλλη — καμία δεν φεύγει σιωπηλά.
      final callId = await newCall(ticketId: '4821');
      final taskId = await newTask(callId: callId);
      await lansweeperRepo.markSubmitted(taskId: taskId, ticketId: '4900');

      final fromTask = await crosscheck.forTask(linkedCallId: callId);
      final fromCall = await crosscheck.forCall(callId: callId);

      expect(fromTask!.ticketId, '4821');
      expect(fromCall!.ticketId, '4900');
    });
  });
}
