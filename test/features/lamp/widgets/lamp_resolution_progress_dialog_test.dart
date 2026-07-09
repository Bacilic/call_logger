import 'dart:async';

import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/resolution_log_entry.dart';
import 'package:call_logger/features/lamp/widgets/lamp_resolution_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lampResolutionEtaText', () {
    test('90 δευτερόλεπτα → 1:30', () {
      expect(
        lampResolutionEtaText(const Duration(seconds: 90)),
        '1:30',
      );
    });

    test('45 δευτερόλεπτα → 0:45', () {
      expect(
        lampResolutionEtaText(const Duration(seconds: 45)),
        '0:45',
      );
    });
  });

  group('lampResolutionRunningStatusText', () {
    test('x/N και Απομένουν ενημερώνονται με βάση την πρόοδο', () {
      expect(
        lampResolutionRunningStatusText(
          processed: 2,
          totalSteps: 5,
          estimatedRemaining: const Duration(seconds: 60),
        ),
        'Η επίλυση εκτελείται. Επιλύθηκαν 2 από 5 · Απομένουν 3 — '
        'Ολοκλήρωση σε 1:00',
      );

      expect(
        lampResolutionRunningStatusText(
          processed: 4,
          totalSteps: 5,
          estimatedRemaining: const Duration(seconds: 15),
        ),
        contains('Επιλύθηκαν 4 από 5'),
      );
      expect(
        lampResolutionRunningStatusText(
          processed: 4,
          totalSteps: 5,
          estimatedRemaining: const Duration(seconds: 15),
        ),
        contains('Απομένουν 1'),
      );
    });

    test('πριν την πρώτη ολοκληρωμένη πρόταση εμφανίζει «υπολογίζεται…»', () {
      expect(
        lampResolutionRunningStatusText(
          processed: 0,
          totalSteps: 3,
          estimatedRemaining: null,
        ),
        'Η επίλυση εκτελείται. Επιλύθηκαν 0 από 3 · Απομένουν 3 — '
        'Ολοκλήρωση σε υπολογίζεται…',
      );
    });
  });

  group('LampResolutionProgressDialog', () {
    Future<ScrollController> pumpDialog(
      WidgetTester tester, {
      required ResolutionLogController logController,
      required ValueNotifier<int> progress,
      required ValueNotifier<bool> paused,
      required int totalSteps,
      Future<LampIssueResolutionApplyResult> Function()? apply,
    }) async {
      final cancelToken = ResolutionCancelToken();
      final applyCompleter = Completer<LampIssueResolutionApplyResult>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => LampResolutionProgressDialog(
                        title: 'Δοκιμή ETL',
                        logController: logController,
                        cancelToken: cancelToken,
                        totalSteps: totalSteps,
                        progress: progress,
                        paused: paused,
                        apply: apply ?? () => applyCompleter.future,
                      ),
                    );
                  },
                  child: const Text('Άνοιγμα'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pump();
      await tester.pump();

      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      return scrollable.controller!;
    }

    Future<void> closeDialog(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets(
      'ενημερώνει το κείμενο κατάστασης όταν αλλάζει το progress ValueNotifier',
      (tester) async {
        final logController = ResolutionLogController();
        final progress = ValueNotifier<int>(0);
        final paused = ValueNotifier<bool>(false);
        addTearDown(() {
          progress.dispose();
          paused.dispose();
        });

        await pumpDialog(
          tester,
          logController: logController,
          progress: progress,
          paused: paused,
          totalSteps: 4,
        );

        expect(find.textContaining('Επιλύθηκαν 0 από 4'), findsOneWidget);
        expect(find.textContaining('υπολογίζεται…'), findsOneWidget);
        expect(find.textContaining('Γραμμές αναφοράς'), findsNothing);

        progress.value = 2;
        await tester.pump();

        expect(find.textContaining('Επιλύθηκαν 2 από 4'), findsOneWidget);
        expect(find.textContaining('Απομένουν 2'), findsOneWidget);
        expect(find.textContaining('Γραμμές αναφοράς'), findsNothing);

        await closeDialog(tester);
      },
    );

    testWidgets(
      'η μπάρα προόδου είναι καθορισμένη (processed / totalSteps)',
      (tester) async {
        final logController = ResolutionLogController();
        final progress = ValueNotifier<int>(1);
        final paused = ValueNotifier<bool>(false);
        addTearDown(() {
          progress.dispose();
          paused.dispose();
        });

        await pumpDialog(
          tester,
          logController: logController,
          progress: progress,
          paused: paused,
          totalSteps: 4,
        );

        final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(indicator.value, closeTo(0.25, 0.001));

        await closeDialog(tester);
      },
    );

    testWidgets(
      'χρήστης στο τέλος — νέα εγγραφή log κάνει άλμα στο τέλος',
      (tester) async {
        final logController = ResolutionLogController();
        final progress = ValueNotifier<int>(0);
        final paused = ValueNotifier<bool>(false);
        addTearDown(() {
          progress.dispose();
          paused.dispose();
        });

        final controller = await pumpDialog(
          tester,
          logController: logController,
          progress: progress,
          paused: paused,
          totalSteps: 2,
        );

        for (var i = 0; i < 40; i++) {
          logController.add(
            ResolutionLogEntry.info('Γραμμή log $i ${'x' * 80}'),
          );
        }
        await tester.pump();
        await tester.pump();

        expect(controller.hasClients, isTrue);
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump();
        final maxExtentBefore = controller.position.maxScrollExtent;

        logController.add(ResolutionLogEntry.info('Νέα γραμμή στο τέλος'));
        await tester.pump();
        await tester.pump();

        expect(
          controller.position.pixels,
          closeTo(controller.position.maxScrollExtent, 48),
        );
        expect(controller.position.maxScrollExtent, greaterThan(maxExtentBefore));

        await closeDialog(tester);
      },
    );

    testWidgets(
      'χρήστης ψηλότερα — νέα εγγραφή log δεν μετακινεί την κύλιση',
      (tester) async {
        final logController = ResolutionLogController();
        final progress = ValueNotifier<int>(0);
        final paused = ValueNotifier<bool>(false);
        addTearDown(() {
          progress.dispose();
          paused.dispose();
        });

        final controller = await pumpDialog(
          tester,
          logController: logController,
          progress: progress,
          paused: paused,
          totalSteps: 2,
        );

        for (var i = 0; i < 40; i++) {
          logController.add(
            ResolutionLogEntry.info('Γραμμή log $i ${'x' * 80}'),
          );
        }
        await tester.pump();
        await tester.pump();

        controller.jumpTo(0);
        await tester.pump();

        final pixelsBefore = controller.position.pixels;
        expect(pixelsBefore, 0);

        logController.add(ResolutionLogEntry.info('Νέα γραμμή — χωρίς άλμα'));
        await tester.pump();
        await tester.pump();

        expect(controller.position.pixels, pixelsBefore);

        await closeDialog(tester);
      },
    );
  });
}
