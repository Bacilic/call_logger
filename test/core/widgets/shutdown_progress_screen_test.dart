import 'dart:async';

import 'package:call_logger/core/services/shutdown_coordinator.dart';
import 'package:call_logger/core/widgets/shutdown_progress_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShutdownProgressScreen', () {
    testWidgets('εμφανίζει βήματα, χρονόμετρο και ένδειξη διακόπηκε', (
      tester,
    ) async {
      final controller = StreamController<ShutdownStepEvent>.broadcast(
        sync: true,
      );
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ShutdownProgressScreen(events: controller.stream),
        ),
      );

      expect(find.text('Κλείσιμο εφαρμογής'), findsOneWidget);
      expect(find.text('Αποθήκευση θέσης παραθύρου'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);

      controller.add(
        const ShutdownStepEvent(
          stepIndex: 0,
          label: 'Αποθήκευση θέσης παραθύρου',
          phase: ShutdownStepPhase.started,
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);

      controller.add(
        const ShutdownStepEvent(
          stepIndex: 0,
          label: 'Αποθήκευση θέσης παραθύρου',
          phase: ShutdownStepPhase.completed,
          durationMs: 1200,
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('1.2s'), findsOneWidget);

      controller.add(
        const ShutdownStepEvent(
          stepIndex: 1,
          label: 'Συγχώνευση αρχείων βάσης',
          phase: ShutdownStepPhase.started,
        ),
      );
      controller.add(
        const ShutdownStepEvent(
          stepIndex: 1,
          label: 'Συγχώνευση αρχείων βάσης',
          phase: ShutdownStepPhase.interrupted,
        ),
      );
      await tester.pump();
      expect(find.text('διακόπηκε'), findsOneWidget);
    });

    testWidgets(
      'scheduleShutdownProgressReveal: δεν εμφανίζεται σε γρήγορο κλείσιμο',
      (tester) async {
        var revealed = false;
        var stillRunning = true;

        final timer = scheduleShutdownProgressReveal(
          delay: const Duration(milliseconds: 500),
          onReveal: () => revealed = true,
          isShutdownStillRunning: () => stillRunning,
        );
        addTearDown(timer.cancel);

        stillRunning = false;
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          revealed,
          isFalse,
          reason: greekExpectMsg(
            'Γρήγορο κλείσιμο δεν πρέπει να δείξει οθόνη προόδου',
          ),
        );
      },
    );

    testWidgets(
      'scheduleShutdownProgressReveal: εμφανίζεται μετά τα 500 ms',
      (tester) async {
        var revealed = false;
        const stillRunning = true;

        final timer = scheduleShutdownProgressReveal(
          delay: const Duration(milliseconds: 500),
          onReveal: () => revealed = true,
          isShutdownStillRunning: () => stillRunning,
        );
        addTearDown(timer.cancel);

        await tester.pump(const Duration(milliseconds: 499));
        expect(revealed, isFalse);

        await tester.pump(const Duration(milliseconds: 1));
        expect(
          revealed,
          isTrue,
          reason: greekExpectMsg(
            'Μετά τα 500 ms πρέπει να εμφανιστεί η οθόνη προόδου',
          ),
        );
      },
    );
  });
}
