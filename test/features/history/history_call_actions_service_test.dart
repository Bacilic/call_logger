// Διαγραφή κλήσης από το Ιστορικό: οι οθόνες που δείχνουν κλήσεις και
// εκκρεμότητες ξαναδιαβάζουν τη βάση — από την ΙΔΙΑ κοινή ανανέωση που
// χρησιμοποιεί η φόρμα κλήσεων, όχι από χειρόγραφο αντίγραφο.
//
//   flutter test test/features/history/history_call_actions_service_test.dart

import 'dart:async';

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/providers/history_call_actions_provider.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

/// Εκτελεί μια ενέργεια του Ιστορικού μέχρι το τέλος: η δουλειά στη βάση τρέχει
/// σε πραγματικό χρόνο, και η ανανέωση των οθονών περιμένει το επόμενο καρέ.
Future<void> _runAction(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  var done = false;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      action().then(
        (_) => done = true,
        onError: (Object e) {
          failure = e;
          done = true;
        },
      ),
    );
  });
  // Πραγματικός χρόνος για τη βάση, καρέ για την ανανέωση — εναλλάξ, μέχρι
  // να τελειώσει η ενέργεια. Το όριο υπάρχει μόνο για να μην κρεμάσει.
  for (var i = 0; i < 200 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  if (failure != null) throw failure!;
  expect(done, isTrue, reason: 'Η ενέργεια του Ιστορικού δεν ολοκληρώθηκε');
}

/// Ό,τι δείχνουν οι τρεις οθόνες — διαβασμένο από τη μνήμη τους, όχι από τη
/// βάση: αν η ανανέωση δεν έγινε, εδώ φαίνεται η μπαγιάτικη τιμή.
Future<({int calls, List<int> orphans, int tasks})> _screens(
  ProviderContainer container,
) async {
  return (
    calls: await container.read(totalCallsCountProvider.future),
    orphans: [
      for (final o in await container.read(orphanCallsProvider.future)) o.id,
    ],
    tasks: await container.read(totalTasksCountProvider.future),
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  testWidgets(
    'διαγραφή από το Ιστορικό: ξαναδιαβάζονται πλήθος κλήσεων, κλήσεις χωρίς εκκρεμότητα και πλήθος εκκρεμοτήτων',
    (tester) async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      final ids = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final calls = CallsRepository(db);
        final orphanId = await calls.insertCall(
          CallModel(
            phoneText: kTestPhoneDigits,
            issue: 'HCA_ORPHAN',
            status: 'pending',
          ),
        );
        final withTaskId = await calls.insertCall(
          CallModel(
            phoneText: kTestPhoneDigits,
            issue: 'HCA_WITH_TASK',
            status: 'pending',
          ),
        );
        await TasksRepository().createFromCall(
          callId: withTaskId,
          callerName: 'Δοκιμή',
          description: 'HCA_TASK',
          callDate: DateTime.now(),
        );
        return (orphan: orphanId, withTask: withTaskId);
      });

      // Οι οθόνες «κρατούν» τις τιμές τους όσο τις κοιτάζει κάποιος. Οι
      // ακροατές στήνονται σε πραγματικό χρόνο: η ανάγνωση της βάσης που
      // ξεκινούν δεν προχωρά ποτέ κάτω από το εικονικό ρολόι του τεστ.
      final before = await tester.runAsync(() async {
        container.listen(totalCallsCountProvider, (_, _) {});
        container.listen(orphanCallsProvider, (_, _) {});
        container.listen(totalTasksCountProvider, (_, _) {});
        return _screens(container);
      });
      expect(before!.orphans, contains(ids!.orphan));

      final service = container.read(historyCallActionsServiceProvider);
      await _runAction(
        tester,
        () => service.deleteCall(ids.orphan, taskAction: 'cascade'),
      );
      await _runAction(
        tester,
        () => service.deleteCall(ids.withTask, taskAction: 'cascade'),
      );

      final after = await tester.runAsync(() => _screens(container));
      // Η ανανέωση αφήνει προγραμματισμένο έναν μηδενικό χρονοδιακόπτη· ένα
      // καρέ τον εκτελεί πριν κλείσει το τεστ.
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        after!.calls,
        before.calls - 2,
        reason: greekExpectMsg(
          'Το συνολικό πλήθος κλήσεων ακολουθεί τη διαγραφή από το Ιστορικό',
        ),
      );
      expect(
        after.orphans,
        isNot(contains(ids.orphan)),
        reason: greekExpectMsg(
          'Η σβησμένη κλήση δεν μένει στις «κλήσεις χωρίς εκκρεμότητα»',
        ),
      );
      expect(
        after.tasks,
        before.tasks - 1,
        reason: greekExpectMsg(
          'Ο μετρητής εκκρεμοτήτων ακολουθεί την εκκρεμότητα που σβήστηκε '
          'μαζί με την κλήση',
        ),
      );
    },
  );
}
