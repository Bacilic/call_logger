// Ο ΕΝΑΣ διάλογος που μαζεύει ό,τι περιμένει τον άνθρωπο.
//
// Ποτέ ουρά διαλόγων: μία ειδοποίηση ή είκοσι, ο διάλογος είναι ένας. Πάνω
// από πέντε συνοψίζονται, και το «Εντάξει» σημαίνει «τα είδα όλα».
//
//   flutter test test/features/tasks/task_notifications_dialog_test.dart

import 'package:call_logger/features/operators/providers/operator_directory_providers.dart';
import 'package:call_logger/features/tasks/models/task_notification.dart';
import 'package:call_logger/features/tasks/widgets/task_notifications_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kOpenButton = 'OPEN_NOTIFICATIONS';

TaskNotification _notification({
  required int id,
  TaskNotificationKind kind = TaskNotificationKind.assigned,
  int? actorId = 22,
  String title = 'Δεν τυπώνει ο εκτυπωτής του ΤΕΠ',
  String? closureNote,
}) => TaskNotification(
  id: id,
  taskId: id,
  kind: kind,
  taskTitle: title,
  createdAt: DateTime(2026, 9, 14, 9, 12),
  actorOperatorId: actorId,
  closureNote: closureNote,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TaskNotificationsDialogResult? result;

  Future<void> open(
    WidgetTester tester,
    List<TaskNotification> notifications,
  ) async {
    result = null;
    // Πραγματικό παράθυρο: το προεπιλεγμένο 800x600 των τεστ είναι κάτω από το
    // ελάχιστο μέγεθος της εφαρμογής, και κάθε διάλογος δείχνει να ξεχειλίζει
    // σε μέγεθος που κανείς δεν βλέπει ποτέ.
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operatorNamesProvider.overrideWith(
            (ref) async => {11: 'Βασίλης', 22: 'Βλάσης'},
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showTaskNotificationsDialog(
                      context,
                      notifications: notifications,
                    );
                  },
                  child: const Text(_kOpenButton),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(_kOpenButton));
    await tester.pumpAndSettle();
  }

  group('Ένα στοιχείο', () {
    testWidgets('ανάθεση: τίτλος που ονομάζει το γεγονός', (tester) async {
      await open(tester, [_notification(id: 1)]);

      expect(find.text('Νέα εκκρεμότητα για εσάς'), findsOneWidget);
      expect(find.text('Δεν τυπώνει ο εκτυπωτής του ΤΕΠ'), findsOneWidget);
      expect(find.textContaining('Ανέθεσε: Βλάσης'), findsOneWidget);
    });

    testWidgets('κλείσιμο: δικός του τίτλος και ρήμα', (tester) async {
      await open(tester, [
        _notification(id: 1, kind: TaskNotificationKind.closed),
      ]);

      expect(find.text('Μια εκκρεμότητά σας έκλεισε'), findsOneWidget);
      expect(find.textContaining('Έκλεισε: Βλάσης'), findsOneWidget);
    });

    testWidgets('αφαίρεση ανάθεσης: δικός του τίτλος και ρήμα', (tester) async {
      await open(tester, [
        _notification(id: 1, kind: TaskNotificationKind.unassigned),
      ]);

      expect(
        find.text('Μια εκκρεμότητα δεν είναι πια δική σας'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Αφαίρεσε την ανάθεση: Βλάσης'),
        findsOneWidget,
      );
    });

    testWidgets('καμία σύνοψη όταν είναι ένα', (tester) async {
      await open(tester, [_notification(id: 1)]);

      expect(find.textContaining('ανατέθηκαν σε εσάς'), findsNothing);
    });

    testWidgets('το κουμπί οδηγεί στη μία κάρτα', (tester) async {
      await open(tester, [_notification(id: 1)]);

      expect(find.text('Άνοιγμα εκκρεμότητας'), findsOneWidget);
    });

    testWidgets('κλείσιμο: φαίνεται ΚΑΙ ο λόγος, όχι μόνο το γεγονός', (
      tester,
    ) async {
      await open(tester, [
        _notification(
          id: 1,
          kind: TaskNotificationKind.closed,
          closureNote: 'Αντικαταστάθηκε το τύμπανο',
        ),
      ]);

      expect(find.text('Αντικαταστάθηκε το τύμπανο'), findsOneWidget);
    });

    testWidgets('κλείσιμο χωρίς λόγο: τίποτα δεν προστίθεται', (tester) async {
      // Κενό κείμενο δεν είναι λόγος: μια άδεια γραμμή κάτω από τον τίτλο
      // μοιάζει με σφάλμα εμφάνισης.
      await open(tester, [
        _notification(
          id: 1,
          kind: TaskNotificationKind.closed,
          closureNote: '   ',
        ),
      ]);

      expect(find.text('   '), findsNothing);
    });
  });

  group('Πολλά μαζί', () {
    testWidgets('το κουμπί δεν υπόσχεται άνοιγμα όταν είναι πολλές', (
      tester,
    ) async {
      // Με πολλές δεν υπάρχει μία εκκρεμότητα να ανοίξει — η ετικέτα λέει
      // αυτό που όντως συμβαίνει.
      await open(tester, [_notification(id: 1), _notification(id: 2)]);

      expect(find.text('Μετάβαση στις Εκκρεμότητες'), findsOneWidget);
      expect(find.text('Άνοιγμα εκκρεμότητας'), findsNothing);
    });

    testWidgets('τίτλος απουσίας και σύνοψη ανά είδος', (tester) async {
      await open(tester, [
        _notification(id: 1),
        _notification(id: 2),
        _notification(id: 3, kind: TaskNotificationKind.closed),
      ]);

      expect(find.text('Όσο λείπατε'), findsOneWidget);
      expect(
        find.text('2 ανατέθηκαν σε εσάς · 1 δική σας έκλεισε'),
        findsOneWidget,
      );
      expect(find.text('Μετάβαση στις Εκκρεμότητες'), findsOneWidget);
    });

    testWidgets('πάνω από πέντε: δείχνει πέντε και συνοψίζει τα υπόλοιπα', (
      tester,
    ) async {
      await open(tester, [
        for (var i = 1; i <= 8; i++)
          _notification(id: i, title: 'Εκκρεμότητα $i'),
      ]);

      expect(find.text('Εκκρεμότητα 1'), findsOneWidget);
      expect(find.text('Εκκρεμότητα 5'), findsOneWidget);
      expect(find.text('Εκκρεμότητα 6'), findsNothing);
      expect(find.text('και 3 ακόμη…'), findsOneWidget);
    });

    testWidgets('ακριβώς πέντε: καμία περικοπή', (tester) async {
      await open(tester, [
        for (var i = 1; i <= 5; i++)
          _notification(id: i, title: 'Εκκρεμότητα $i'),
      ]);

      expect(find.textContaining('ακόμη…'), findsNothing);
    });
  });

  group('Η απάντηση του ανθρώπου', () {
    testWidgets('«Εντάξει» χωρίς τικ: ούτε σίγαση ούτε πλοήγηση', (
      tester,
    ) async {
      await open(tester, [_notification(id: 1)]);

      await tester.tap(find.widgetWithText(FilledButton, 'Εντάξει'));
      await tester.pumpAndSettle();

      expect(result?.silenceFuture, isFalse);
      expect(result?.openTasks, isFalse);
    });

    testWidgets('το κουτάκι ζητά σίγαση', (tester) async {
      await open(tester, [_notification(id: 1)]);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Εντάξει'));
      await tester.pumpAndSettle();

      expect(result?.silenceFuture, isTrue);
    });

    testWidgets('το άνοιγμα κρατά και το τικ', (tester) async {
      await open(tester, [_notification(id: 1)]);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Άνοιγμα εκκρεμότητας'));
      await tester.pumpAndSettle();

      expect(result?.openTasks, isTrue);
      expect(
        result?.silenceFuture,
        isTrue,
        reason: 'Η σίγαση δεν χάνεται επειδή διάλεξε να δει τη λίστα.',
      );
    });
  });
}
