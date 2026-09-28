// Το αντίγραφο εξόδου δεν μοιράζεται το ρολόι ασφαλείας με τα άλλα βήματα.
//
//   flutter test test/core/services/exit_backup_gets_its_own_window_test.dart

import 'dart:async';

import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

/// Ρολόι που προχωρά μόνο όταν του το πουν, με ουρά αναμονών.
///
/// Χρειάζεται πιστότερο ψεύτικο ρολόι από ένα `delay` που επιστρέφει αμέσως:
/// το ερώτημα του γύρου είναι **πόσος χρόνος** πέρασε σε ποιο βήμα, οπότε η
/// αναμονή πρέπει να ξυπνά όταν περάσει η ώρα της και όχι νωρίτερα.
class _ManualClock {
  _ManualClock(this.now);

  DateTime now;
  final List<_Wait> _waiting = [];

  Future<void> delay(Duration duration) {
    final wait = _Wait(now.add(duration));
    _waiting.add(wait);
    return wait.completer.future;
  }

  Future<void> advance(Duration duration) async {
    now = now.add(duration);
    final due = _waiting.where((w) => !w.at.isAfter(now)).toList();
    for (final wait in due) {
      _waiting.remove(wait);
      if (!wait.completer.isCompleted) wait.completer.complete();
    }
    // Αφήνουμε την ουρά μικροεργασιών να τρέξει, ώστε ό,τι ξύπνησε να
    // προλάβει να αντιδράσει πριν προχωρήσει το τεστ.
    await Future<void>.delayed(Duration.zero);
  }
}

class _Wait {
  _Wait(this.at);

  final DateTime at;
  final Completer<void> completer = Completer<void>();
}

void main() {
  final t0 = DateTime(2026, 9, 21, 8, 38);

  group('το κλείσιμο με δικτυακή βάση', () {
    test(
      'το αντίγραφο δεν πληρώνει τον χρόνο των προηγούμενων βημάτων',
      () async {
        // Το μετρημένο κλείσιμο της 21/09: τα τρία πρώτα βήματα έφαγαν εννιά
        // δευτερόλεπτα και το αντίγραφο ήθελε δεκαέξι. Μαζί ξεπερνούν το όριο
        // των είκοσι — και η εφαρμογή τερματίστηκε βίαια στη μέση του τέταρτου.
        final clock = _ManualClock(t0);
        final order = <String>[];
        final events = <ShutdownStepEvent>[];

        Future<void> Function() step(String name, Duration cost) {
          return () async {
            order.add(name);
            await clock.advance(cost);
          };
        }

        final coordinator = ShutdownCoordinator(
          safetyTimeout: const Duration(seconds: 20),
          now: () => clock.now,
          delay: clock.delay,
          persistWindowBounds: step('persist', const Duration(seconds: 3)),
          releasePresence: step('release', const Duration(seconds: 3)),
          walCheckpoint: step('wal', const Duration(seconds: 3)),
          exitBackup: step('backup', const Duration(seconds: 16)),
          closeConnection: step('closeDb', const Duration(seconds: 1)),
          closeCrashLog: step('crashLog', const Duration(seconds: 1)),
          terminate: () => order.add('terminate'),
        );

        final sub = coordinator.events.listen(events.add);
        await coordinator.run();
        await sub.cancel();

        expect(
          order,
          [
            'persist',
            'release',
            'wal',
            'backup',
            'closeDb',
            'crashLog',
            'terminate',
          ],
          reason: greekExpectMsg(
            'Το αντίγραφο έχει δικό του παράθυρο, οπότε τα δύο τελευταία βήματα '
            'προλαβαίνουν να τρέξουν',
          ),
        );
        expect(
          events.where((e) => e.phase == ShutdownStepPhase.interrupted),
          isEmpty,
          reason: greekExpectMsg(
            'Κανένα βήμα δεν διακόπηκε από το γενικό όριο',
          ),
        );
        expect(
          events.where((e) => e.phase == ShutdownStepPhase.completed).length,
          6,
        );
      },
    );

    test(
      'η υπέρβαση του δικού του παραθύρου δεν σκοτώνει τα επόμενα βήματα',
      () async {
        // Όταν το αντίγραφο κολλήσει, χάνεται το αντίγραφο — όχι το κλείσιμο
        // της σύνδεσης και το σβήσιμο του σημαδιού «τρέχω τώρα» που έρχονται
        // μετά. Παλιότερα πέθαιναν κι αυτά μαζί του.
        final clock = _ManualClock(t0);
        final order = <String>[];
        final events = <ShutdownStepEvent>[];

        final coordinator = ShutdownCoordinator(
          safetyTimeout: const Duration(seconds: 20),
          now: () => clock.now,
          delay: clock.delay,
          persistWindowBounds: () async {},
          releasePresence: () async {},
          walCheckpoint: () async {},
          exitBackup: () {
            order.add('backup');
            // Ο χρόνος περνά ΑΦΟΥ ο συντονιστής στήσει το παράθυρο του βήματος.
            scheduleMicrotask(() => clock.advance(const Duration(seconds: 25)));
            return Completer<void>().future; // δεν τελειώνει ποτέ
          },
          closeConnection: () async => order.add('closeDb'),
          closeCrashLog: () async => order.add('crashLog'),
          terminate: () => order.add('terminate'),
        );

        final sub = coordinator.events.listen(events.add);
        await coordinator.run();
        await sub.cancel();

        expect(
          order,
          ['backup', 'closeDb', 'crashLog', 'terminate'],
          reason: greekExpectMsg(
            'Το κολλημένο αντίγραφο εγκαταλείπεται, η ουρά συνεχίζει',
          ),
        );

        final failed = events.where((e) => e.phase == ShutdownStepPhase.failed);
        expect(failed.length, 1);
        expect(failed.single.label, 'Αντίγραφο ασφαλείας εξόδου');
        expect(
          failed.single.error,
          isA<ShutdownStepBudgetExceeded>(),
          reason: greekExpectMsg(
            'Το ίχνος πρέπει να λέει ότι ξεπεράστηκε παράθυρο, όχι «Future not '
            'completed»',
          ),
        );
      },
    );

    test(
      'το γενικό όριο εξακολουθεί να διακόπτει βήμα χωρίς δικό του παράθυρο',
      () async {
        // Ο φρουρός δεν χαλάρωσε: ένα βήμα που δεν έχει δικό του χρόνο και
        // κρεμάει, σκοτώνει το κλείσιμο όπως πριν.
        final clock = _ManualClock(t0);
        var terminated = false;
        final events = <ShutdownStepEvent>[];

        final coordinator = ShutdownCoordinator(
          safetyTimeout: const Duration(seconds: 20),
          now: () => clock.now,
          delay: clock.delay,
          persistWindowBounds: () {
            scheduleMicrotask(() => clock.advance(const Duration(seconds: 21)));
            return Completer<void>().future;
          },
          releasePresence: () async {},
          walCheckpoint: () async {},
          exitBackup: () async {},
          closeConnection: () async {},
          closeCrashLog: () async {},
          terminate: () => terminated = true,
        );

        final sub = coordinator.events.listen(events.add);
        await coordinator.run();
        await sub.cancel();

        expect(terminated, isTrue);
        expect(
          events
              .where((e) => e.phase == ShutdownStepPhase.interrupted)
              .single
              .label,
          'Αποθήκευση θέσης παραθύρου',
        );
      },
    );

    test(
      'το σημάδι «τρέχω τώρα» σβήνει ακόμη κι όταν το όριο διακόψει',
      () async {
        // Το σβήσιμο είναι τελευταίο στην ουρά, άρα ήταν το πρώτο που χανόταν.
        // Όσο έμενε ανεκτέλεστο, η επόμενη εκκίνηση ανήγγελλε μη ομαλό κλείσιμο
        // και ο φρουρός της αναβάθμισης έβλεπε σταθμό-φάντασμα επί τρία λεπτά.
        final clock = _ManualClock(t0);
        var markCleared = 0;

        final coordinator = ShutdownCoordinator(
          safetyTimeout: const Duration(seconds: 20),
          now: () => clock.now,
          delay: clock.delay,
          persistWindowBounds: () {
            scheduleMicrotask(() => clock.advance(const Duration(seconds: 21)));
            return Completer<void>().future; // κολλάει και ρίχνει το κλείσιμο
          },
          releasePresence: () async {},
          walCheckpoint: () async {},
          exitBackup: () async {},
          closeConnection: () async {},
          closeCrashLog: () async => markCleared++,
          terminate: () {},
        );

        await coordinator.run();

        expect(
          markCleared,
          1,
          reason: greekExpectMsg(
            'Το κλείσιμο του ημερολογίου δεν φτάνει ποτέ στην ουρά — οφείλει να '
            'τρέξει στη διαδρομή του τερματισμού',
          ),
        );
      },
    );

    test('σε ομαλό κλείσιμο το σημάδι δεν σβήνεται δύο φορές', () async {
      var markCleared = 0;
      final coordinator = ShutdownCoordinator(
        persistWindowBounds: () async {},
        releasePresence: () async {},
        walCheckpoint: () async {},
        exitBackup: () async {},
        closeConnection: () async {},
        closeCrashLog: () async => markCleared++,
        terminate: () {},
      );

      await coordinator.run();

      expect(markCleared, 1);
    });

    test('κάθε βήμα δηλώνει αν έχει δικό του παράθυρο', () {
      // Ένα βήμα που προστίθεται στη μία λίστα και ξεχνιέται στην άλλη θα
      // κληρονομούσε σιωπηλά λάθος όριο.
      expect(
        ShutdownCoordinator.stepOwnBudgets.length,
        ShutdownCoordinator.stepLabels.length,
      );
      final withOwnWindow = [
        for (var i = 0; i < ShutdownCoordinator.stepLabels.length; i++)
          if (ShutdownCoordinator.stepOwnBudgets[i] != null)
            ShutdownCoordinator.stepLabels[i],
      ];
      expect(withOwnWindow, ['Αντίγραφο ασφαλείας εξόδου']);
    });
  });
}
