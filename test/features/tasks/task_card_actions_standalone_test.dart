// Η ζώνη σημάτων και ενεργειών στήνεται ΧΩΡΙΣ την κάρτα που τη φιλοξενεί.
//
// Αυτό ήταν το ζητούμενο της διάσπασης: όσο η ζώνη ζούσε μέσα στο ενιαίο
// `build` της κάρτας, για να δοκιμαστεί έπρεπε να στηθεί ολόκληρη η κάρτα —
// με τους providers της, τη βάση και την κατάσταση διαγραφής. Εδώ δεν υπάρχει
// ούτε ProviderScope: αν κάποτε επιστρέψει εξάρτηση από την κάρτα, αυτό το
// τεστ σκάει πρώτο.
//
//   flutter test test/features/tasks/task_card_actions_standalone_test.dart

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/widgets/task_card_actions.dart';
import 'package:call_logger/features/tasks/widgets/task_card_callbacks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task task({int? createdBy, int? assignedTo, int? priority}) => Task(
    id: 1,
    title: 'Προς δοκιμή',
    dueDate: '2026-09-01T10:00:00.000',
    status: 'open',
    priority: priority,
    createdByOperatorId: createdBy,
    assignedOperatorId: assignedTo,
  );

  Future<void> pumpActions(
    WidgetTester tester, {
    required Task subject,
    String? assigneeName,
    String? creatorName,
    TaskCardCallbacks callbacks = const TaskCardCallbacks(),
    Set<int> disabledOperatorIds = const {},
    Map<int, String?> operatorAvatars = const <int, String?>{},
    bool hasSolution = false,
    bool showSolution = false,
    VoidCallback? onToggleSolution,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCardActions(
            task: subject,
            callbacks: callbacks,
            status: TaskStatusX.fromString(subject.status),
            assigneeName: assigneeName,
            creatorName: creatorName,
            operatorAvatars: operatorAvatars,
            disabledOperatorIds: disabledOperatorIds,
            deleteMenuEnabled: true,
            hasSolution: hasSolution,
            showSolution: showSolution,
            onToggleSolution: onToggleSolution ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Ζώνη σημάτων και ενεργειών, αυτόνομα', () {
    testWidgets('δείχνει και τα δύο πρόσωπα όταν διαφέρουν', (tester) async {
      await pumpActions(
        tester,
        subject: task(createdBy: 11, assignedTo: 22),
        assigneeName: 'Βλάσης',
        creatorName: 'Βασίλης',
      );

      expect(find.text('Βλάσης'), findsOneWidget);
      expect(find.text('Άνοιξε: Βασίλης'), findsOneWidget);
    });

    testWidgets('ίδιο πρόσωπο: ο δημιουργός δεν επαναλαμβάνεται', (
      tester,
    ) async {
      await pumpActions(
        tester,
        subject: task(createdBy: 22, assignedTo: 22),
        assigneeName: 'Βλάσης',
        creatorName: 'Βλάσης',
      );

      expect(find.text('Άνοιξε: Βλάσης'), findsNothing);
      expect(find.text('Βλάσης'), findsOneWidget);
    });

    testWidgets('το κουμπί λύσης αναφέρει τι θα κάνει το πάτημα', (
      tester,
    ) async {
      var toggles = 0;
      await pumpActions(
        tester,
        subject: task(),
        hasSolution: true,
        onToggleSolution: () => toggles++,
      );

      expect(find.text('Προηγούμενη λύση'), findsOneWidget);
      await tester.tap(find.text('Προηγούμενη λύση'));
      expect(toggles, 1);
    });

    testWidgets('χωρίς λύση δεν υπάρχει κουμπί λύσης', (tester) async {
      await pumpActions(tester, subject: task());

      expect(find.text('Προηγούμενη λύση'), findsNothing);
      expect(find.text('Λύση'), findsNothing);
    });

    testWidgets('η ολοκλήρωση εμφανίζεται μόνο όταν η οθόνη την προσφέρει', (
      tester,
    ) async {
      await pumpActions(tester, subject: task());
      expect(find.byTooltip('Ολοκλήρωση'), findsNothing);

      await pumpActions(
        tester,
        subject: task(),
        callbacks: TaskCardCallbacks(onComplete: () {}),
      );
      expect(find.byTooltip('Ολοκλήρωση'), findsOneWidget);
    });

    testWidgets('το απενεργοποιημένο προφίλ γράφεται πλάγια', (tester) async {
      await pumpActions(
        tester,
        subject: task(createdBy: 11, assignedTo: 22),
        assigneeName: 'Βλάσης',
        creatorName: 'Βασίλης',
        disabledOperatorIds: const {22},
      );

      final assignee = tester.widget<Text>(find.text('Βλάσης'));
      expect(
        assignee.style?.fontStyle,
        FontStyle.italic,
        reason:
            'Ίδιο σήμα με το «(διαγραμμένο)» των οντοτήτων καταλόγου, που '
            'κάθεται λίγα εικονοστοιχεία παραδίπλα στην ίδια κάρτα.',
      );

      final creator = tester.widget<Text>(find.text('Άνοιξε: Βασίλης'));
      expect(
        creator.style?.fontStyle,
        isNot(FontStyle.italic),
        reason: 'Ο Βασίλης είναι ενεργός — δεν σημαίνεται.',
      );
    });

    testWidgets('η υπόδειξη λέει ότι το προφίλ είναι απενεργοποιημένο', (
      tester,
    ) async {
      await pumpActions(
        tester,
        subject: task(createdBy: 11),
        creatorName: 'Βασίλης',
        disabledOperatorIds: const {11},
      );

      expect(
        find.byTooltip('Δημιουργός της εκκρεμότητας (απενεργοποιημένο προφίλ)'),
        findsOneWidget,
      );
    });

    testWidgets('χωρίς προτεραιότητα δεν μπαίνει σήμα προτεραιότητας', (
      tester,
    ) async {
      await pumpActions(tester, subject: task());
      expect(find.text('Υψηλή'), findsNothing);
      expect(find.text('Κρίσιμη'), findsNothing);

      await pumpActions(tester, subject: task(priority: 2));
      expect(find.text('Κρίσιμη'), findsOneWidget);
    });
  });
}
