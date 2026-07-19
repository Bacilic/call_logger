import 'dart:async';

import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  group('ShutdownCoordinator', () {
    test(
      'νέα ροή: terminate μετά από όλα τα βήματα· τελευταίο το κλείσιμο ημερολογίου',
      () async {
        final order = <String>[];
        var terminateCount = 0;

        final coordinator = ShutdownCoordinator(
          persistWindowBounds: () async => order.add('persist'),
          walCheckpoint: () async => order.add('wal'),
          exitBackup: () async => order.add('backup'),
          closeConnection: () async => order.add('closeDb'),
          closeCrashLog: () async => order.add('crashLog'),
          terminate: () {
            terminateCount++;
            order.add('terminate');
          },
        );

        final events = <ShutdownStepEvent>[];
        final sub = coordinator.events.listen(events.add);

        await coordinator.run();
        await sub.cancel();

        expect(
          order,
          [
            'persist',
            'wal',
            'backup',
            'closeDb',
            'crashLog',
            'terminate',
          ],
          reason: greekExpectMsg(
            'Η σειρά βημάτων πρέπει να τελειώνει με crash log και μετά terminate',
          ),
        );
        expect(terminateCount, 1);
        expect(
          order.contains('destroy'),
          isFalse,
          reason: greekExpectMsg(
            'Η νέα ροή δεν πρέπει να καλεί windowManager.destroy()',
          ),
        );

        final labels = events
            .where((e) => e.phase == ShutdownStepPhase.started)
            .map((e) => e.label)
            .toList();
        expect(labels, ShutdownCoordinator.stepLabels);

        expect(
          events.where((e) => e.phase == ShutdownStepPhase.completed).length,
          5,
        );
        expect(
          events.lastWhere((e) => e.phase == ShutdownStepPhase.started).label,
          'Κλείσιμο ημερολογίου καταγραφής',
        );
      },
    );

    test('γεγονότα έναρξης και ολοκλήρωσης με διάρκεια ms', () async {
      var clock = DateTime(2026, 7, 19, 10, 0, 0);
      final coordinator = ShutdownCoordinator(
        now: () => clock,
        persistWindowBounds: () async {
          clock = clock.add(const Duration(milliseconds: 12));
        },
        walCheckpoint: () async {
          clock = clock.add(const Duration(milliseconds: 3));
        },
        exitBackup: () async {},
        closeConnection: () async {},
        closeCrashLog: () async {},
        terminate: () {},
      );

      final events = <ShutdownStepEvent>[];
      final sub = coordinator.events.listen(events.add);
      await coordinator.run();
      await sub.cancel();

      final firstDone = events.firstWhere(
        (e) =>
            e.phase == ShutdownStepPhase.completed &&
            e.label == 'Αποθήκευση θέσης παραθύρου',
      );
      expect(firstDone.durationMs, 12);
    });

    test('αποτυχία βήματος καταγράφεται και η ροή συνεχίζει', () async {
      final order = <String>[];
      final coordinator = ShutdownCoordinator(
        persistWindowBounds: () async => order.add('persist'),
        walCheckpoint: () async {
          order.add('wal');
          throw StateError('wal failed');
        },
        exitBackup: () async => order.add('backup'),
        closeConnection: () async => order.add('closeDb'),
        closeCrashLog: () async => order.add('crashLog'),
        terminate: () => order.add('terminate'),
      );

      final events = <ShutdownStepEvent>[];
      final sub = coordinator.events.listen(events.add);
      await coordinator.run();
      await sub.cancel();

      expect(order, [
        'persist',
        'wal',
        'backup',
        'closeDb',
        'crashLog',
        'terminate',
      ]);
      final failed = events.where((e) => e.phase == ShutdownStepPhase.failed);
      expect(failed.length, 1);
      expect(failed.single.label, 'Συγχώνευση αρχείων βάσης');
    });

    test('χρονικό όριο ασφαλείας καλεί terminate και σημειώνει διακόπηκε',
        () async {
      var clock = DateTime(2026, 7, 19, 12, 0, 0);
      final hang = Completer<void>();
      var terminated = false;
      final events = <ShutdownStepEvent>[];

      final coordinator = ShutdownCoordinator(
        safetyTimeout: const Duration(seconds: 20),
        now: () => clock,
        delay: (duration) async {
          clock = clock.add(duration);
        },
        persistWindowBounds: () => hang.future,
        walCheckpoint: () async {},
        exitBackup: () async {},
        closeConnection: () async {},
        closeCrashLog: () async {},
        terminate: () {
          terminated = true;
        },
      );

      final sub = coordinator.events.listen(events.add);
      await coordinator.run();
      await sub.cancel();

      expect(terminated, isTrue);
      expect(
        events.any((e) => e.phase == ShutdownStepPhase.interrupted),
        isTrue,
        reason: greekExpectMsg(
          'Το τρέχον βήμα πρέπει να σημειωθεί ως διακόπηκε',
        ),
      );
      expect(
        events
            .where((e) => e.phase == ShutdownStepPhase.interrupted)
            .single
            .label,
        'Αποθήκευση θέσης παραθύρου',
      );
    });

    test('exit(0) δεν καλείται — μόνο η injectable συνάρτηση τερματισμού',
        () async {
      var terminateCalled = false;
      final coordinator = ShutdownCoordinator(
        persistWindowBounds: () async {},
        walCheckpoint: () async {},
        exitBackup: () async {},
        closeConnection: () async {},
        closeCrashLog: () async {},
        terminate: () {
          terminateCalled = true;
        },
      );
      await coordinator.run();
      expect(terminateCalled, isTrue);
      expect(coordinator.terminateCalled, isTrue);
    });
  });
}
