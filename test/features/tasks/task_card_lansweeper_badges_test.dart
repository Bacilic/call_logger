// Τι λέει η κάρτα της εκκρεμότητας για το Lansweeper: πότε εμφανίζεται το
// σήμα, πότε ο δεσμός με την κλήση, και τι γράφει το μενού.
//
//   flutter test test/features/tasks/task_card_lansweeper_badges_test.dart

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/widgets/task_card_actions.dart';
import 'package:call_logger/features/tasks/widgets/task_card_callbacks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task({
  int? callId,
  String? lansweeperState,
  String? lansweeperMainTicketId,
  String? linkedCallTicketId,
}) {
  return Task(
    id: 7,
    callId: callId,
    title: 'Δεν τυπώνει',
    dueDate: '2026-09-21T14:30:00.000',
    status: 'open',
    lansweeperState: lansweeperState,
    lansweeperMainTicketId: lansweeperMainTicketId,
    linkedCallTicketId: linkedCallTicketId,
  );
}

Widget _wrap(
  Task task, {
  VoidCallback? onSubmitToLansweeper,
  VoidCallback? onPrint,
  VoidCallback? onSaveAsPdf,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: TaskCardActions(
          task: task,
          callbacks: TaskCardCallbacks(
            onSubmitToLansweeper: onSubmitToLansweeper,
            onPrint: onPrint,
            onSaveAsPdf: onSaveAsPdf,
          ),
          status: TaskStatus.open,
          ticketViewUrlTemplate: 'https://tt.example.gr/ticket/{id}',
          assigneeName: null,
          creatorName: null,
          closerName: null,
          operatorAvatars: const <int, String?>{},
          disabledOperatorIds: const <int>{},
          deleteMenuEnabled: true,
          hasSolution: false,
          showSolution: false,
          onToggleSolution: () {},
        ),
      ),
    ),
  );
}

void main() {
  group('το σήμα Lansweeper', () {
    testWidgets('εμφανίζεται όταν υπάρχει αίτημα', (tester) async {
      await tester.pumpWidget(
        _wrap(_task(lansweeperState: 'sent', lansweeperMainTicketId: '4821')),
      );

      expect(find.text('Καταχωρημένη'), findsOneWidget);
    });

    testWidgets('λείπει από εκκρεμότητα που δεν στάλθηκε ποτέ', (tester) async {
      await tester.pumpWidget(_wrap(_task()));

      expect(
        find.text('Ακαταχώρητη'),
        findsNothing,
        reason:
            'η εκκρεμότητα δεν είναι ουρά· ένα σήμα σε κάθε κάρτα θα έκρυβε '
            'τις λίγες που όντως έχουν αίτημα',
      );
    });

    testWidgets('εμφανίζεται και σε αποτυχία χωρίς αριθμό', (tester) async {
      await tester.pumpWidget(_wrap(_task(lansweeperState: 'failed')));

      expect(find.text('Αποτυχημένη'), findsOneWidget);
    });
  });

  group('ο δεσμός με την κλήση', () {
    testWidgets('φαίνεται όταν η εκκρεμότητα γεννήθηκε από κλήση', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_task(callId: 344)));

      expect(find.text('από κλήση #344'), findsOneWidget);
    });

    testWidgets('λείπει από αυτόνομη εκκρεμότητα', (tester) async {
      await tester.pumpWidget(_wrap(_task()));

      expect(find.textContaining('από κλήση'), findsNothing);
    });

    testWidgets('η υπόδειξη ΔΕΝ υποθέτει — λέει ότι η κλήση δεν έχει αίτημα', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_task(callId: 344)));

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('από κλήση #344'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, contains('δεν έχει καταχωρηθεί ακόμα ως αίτημα'));
      expect(
        tooltip.message,
        isNot(contains('Αν εκείνη')),
        reason: 'η εφαρμογή ξέρει την απάντηση· δεν την υποθέτει',
      );
    });

    testWidgets('η υπόδειξη ονομάζει το αίτημα της κλήσης όταν υπάρχει', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_task(callId: 344, linkedCallTicketId: '6005')),
      );

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('από κλήση #344'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, contains('ως αίτημα #6005'));
    });
  });

  group('η ενέργεια αποστολής', () {
    testWidgets('λείπει όταν η οθόνη δεν την προσφέρει', (tester) async {
      await tester.pumpWidget(_wrap(_task()));
      await tester.tap(find.byTooltip('Ενέργειες'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Lansweeper'), findsNothing);
    });

    testWidgets('προσκαλεί σε νέο αίτημα όταν δεν υπάρχει', (tester) async {
      await tester.pumpWidget(_wrap(_task(), onSubmitToLansweeper: () {}));
      await tester.tap(find.byTooltip('Ενέργειες'));
      await tester.pumpAndSettle();

      expect(find.text('Αίτημα στο Lansweeper…'), findsOneWidget);
    });

    testWidgets('δείχνει τον αριθμό όταν το αίτημα υπάρχει ήδη', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _task(lansweeperState: 'sent', lansweeperMainTicketId: '4821'),
          onSubmitToLansweeper: () {},
        ),
      );
      await tester.tap(find.byTooltip('Ενέργειες'));
      await tester.pumpAndSettle();

      expect(
        find.text('Αίτημα Lansweeper #4821…'),
        findsOneWidget,
        reason: 'αλλιώς μοιάζει ότι το πάτημα θα ανοίξει δεύτερο αίτημα',
      );
    });

    testWidgets('το πάτημα φτάνει στη ροή', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _wrap(_task(), onSubmitToLansweeper: () => pressed++),
      );
      await tester.tap(find.byTooltip('Ενέργειες'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Αίτημα στο Lansweeper…'));
      await tester.pumpAndSettle();

      expect(pressed, 1);
    });
  });

  group('η εκτύπωση', () {
    testWidgets('οι δύο επιλογές κάθονται ΠΑΝΩ από τη Διαγραφή', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_task(), onPrint: () {}, onSaveAsPdf: () {}),
      );
      await tester.tap(find.byTooltip('Ενέργειες'));
      await tester.pumpAndSettle();

      final print = tester.getTopLeft(find.text('Εκτύπωση…')).dy;
      final pdf = tester.getTopLeft(find.text('Αποθήκευση ως PDF…')).dy;
      final delete = tester.getTopLeft(find.text('Διαγραφή')).dy;
      expect(print, lessThan(pdf));
      expect(pdf, lessThan(delete));
    });

    testWidgets('λείπουν όταν η οθόνη δεν τις προσφέρει', (tester) async {
      await tester.pumpWidget(_wrap(_task()));
      await tester.tap(find.byTooltip('Ενέργειες'));
      await tester.pumpAndSettle();

      expect(find.text('Εκτύπωση…'), findsNothing);
      expect(find.text('Αποθήκευση ως PDF…'), findsNothing);
    });

    testWidgets('τυπώνεται και ολοκληρωμένη εκκρεμότητα', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaskCardActions(
                task: _task(),
                callbacks: TaskCardCallbacks(onPrint: () {}),
                status: TaskStatus.closed,
                assigneeName: null,
                creatorName: null,
                closerName: null,
                operatorAvatars: const <int, String?>{},
                disabledOperatorIds: const <int>{},
                deleteMenuEnabled: true,
                hasSolution: false,
                showSolution: false,
                onToggleSolution: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Ενέργειες'));
      await tester.pumpAndSettle();

      expect(
        find.text('Εκτύπωση…'),
        findsOneWidget,
        reason: 'το φύλλο της κλεισμένης κουβαλά τη λύση και τις αναβολές της',
      );
    });

    testWidgets('κάθε πάτημα φτάνει στη δική του ροή', (tester) async {
      var printed = 0;
      var saved = 0;
      await tester.pumpWidget(
        _wrap(_task(), onPrint: () => printed++, onSaveAsPdf: () => saved++),
      );

      await tester.tap(find.byTooltip('Ενέργειες'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Εκτύπωση…'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Ενέργειες'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Αποθήκευση ως PDF…'));
      await tester.pumpAndSettle();

      expect(printed, 1);
      expect(saved, 1);
    });
  });
}
