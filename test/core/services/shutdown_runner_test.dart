// Η ενορχήστρωση του τερματισμού, βγαλμένη από το widget.
//
// Φυλάει τη ΣΕΙΡΑ: το UI μαθαίνει για τον συντονιστή πριν ξεκινήσουν τα βήματα,
// μεσολαβεί ένα frame ώστε η οθόνη προόδου να συνδεθεί στο stream, και το UI
// ειδοποιείται για το τέλος ΑΚΟΜΗ ΚΑΙ αν ο τερματισμός σκάσει.
//
//   flutter test test/core/services/shutdown_runner_test.dart

import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:call_logger/core/services/shutdown_runner.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingPresenter implements ShutdownUiPresenter {
  _RecordingPresenter(this.log, {this.frameFailure});

  final List<String> log;

  /// Σφάλμα που πετάει το `awaitNextFrame` (π.χ. το UI πέθανε στο μεταξύ).
  final Object? frameFailure;

  ShutdownCoordinator? shownCoordinator;

  @override
  void onShutdownStarted(ShutdownCoordinator coordinator) {
    shownCoordinator = coordinator;
    log.add('ui:started');
  }

  @override
  Future<void> awaitNextFrame() async {
    if (frameFailure != null) throw frameFailure!;
    log.add('ui:frame');
  }

  @override
  void onShutdownFinished() => log.add('ui:finished');
}

ShutdownCoordinator _coordinatorWritingTo(List<String> log) {
  return ShutdownCoordinator(
    persistWindowBounds: () async => log.add('persist'),
    walCheckpoint: () async => log.add('wal'),
    exitBackup: () async => log.add('backup'),
    closeConnection: () async => log.add('closeDb'),
    closeCrashLog: () async => log.add('crashLog'),
    terminate: () => log.add('terminate'),
  );
}

void main() {
  group('ShutdownRunner', () {
    test('το UI ενημερώνεται ΠΡΙΝ τα βήματα και μεσολαβεί ένα frame', () async {
      final log = <String>[];
      final presenter = _RecordingPresenter(log);

      await ShutdownRunner(
        createCoordinator: () => _coordinatorWritingTo(log),
        createTrace: () async => null,
        presenter: presenter,
      ).run();

      expect(log, [
        'ui:started',
        'ui:frame',
        'persist',
        'wal',
        'backup',
        'closeDb',
        'crashLog',
        'terminate',
        'ui:finished',
      ]);
      expect(presenter.shownCoordinator, isNotNull);
    });

    test('ΤΟ ΚΡΙΣΙΜΟ: το UI ειδοποιείται για το τέλος ακόμη κι αν η ροή '
        'σκάσει στη μέση', () async {
      // Το `coordinator.run()` δεν πετάει ποτέ — πιάνει μόνο του τις αποτυχίες
      // των βημάτων. Η μόνη εξαίρεση που διαφεύγει έρχεται από το UI: αν το
      // κέλυφος πεθάνει όσο περιμένουμε frame. Μόνο το `finally` σώζει τότε.
      final log = <String>[];
      final presenter = _RecordingPresenter(
        log,
        frameFailure: StateError('το κέλυφος πέθανε στο μεταξύ'),
      );

      final runner = ShutdownRunner(
        createCoordinator: () => _coordinatorWritingTo(log),
        createTrace: () async => null,
        presenter: presenter,
      );

      await expectLater(runner.run(), throwsStateError);

      expect(
        log,
        contains('ui:finished'),
        reason:
            'Χωρίς αυτό, ο χρονιστής αποκάλυψης προόδου θα έμενε ενεργός '
            'και η οθόνη θα κολλούσε σε ημιτελές κλείσιμο.',
      );
      expect(log, isNot(contains('terminate')));
    });

    test('δεύτερη κλήση run() δεν ξαναξεκινά τον τερματισμό', () async {
      final log = <String>[];
      final presenter = _RecordingPresenter(log);

      final runner = ShutdownRunner(
        createCoordinator: () => _coordinatorWritingTo(log),
        createTrace: () async => null,
        presenter: presenter,
      );

      await runner.run();
      await runner.run();

      expect(log.where((e) => e == 'terminate').length, 1);
      expect(log.where((e) => e == 'ui:started').length, 1);
      expect(runner.isRunning, isTrue);
    });
  });
}
