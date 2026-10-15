// Το «Χ» με ανοιχτό διάλογο ρωτά· μετά το «Κλείσιμο» τίποτα δεν πατιέται.
//
// Το σενάριο του Διευθυντή (14/10/2026): ανοιχτή «Επεξεργασία Υπαλλήλου»,
// «Χ» της εφαρμογής, και «Αποθήκευση» στον διάλογο που έμενε ορατός — η
// αλλαγή γραφόταν στη βάση μέσα στο κλείσιμο.
//
//   flutter test test/core/widgets/close_with_open_dialog_test.dart

import 'package:call_logger/core/services/app_close_controller.dart';
import 'package:call_logger/core/widgets/app_closing_shield.dart';
import 'package:call_logger/core/widgets/close_with_open_dialog_question.dart';
import 'package:call_logger/core/widgets/draggable_dialog_shell.dart';
import 'package:call_logger/core/widgets/modal_route_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness {
  _Harness() {
    controller = AppCloseController(runShutdown: () async => shutdownRuns++);
    controller.confirmUserClose = () => confirmCloseWithOpenDialog(tracker);
    addTearDown(controller.dispose);
  }

  final tracker = ModalRouteTracker();
  late final AppCloseController controller;
  int shutdownRuns = 0;
  int saves = 0;

  Widget app() => MaterialApp(
    navigatorObservers: [tracker],
    builder: (context, child) =>
        AppClosingShield(controllerForTest: controller, child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Επεξεργασία Υπαλλήλου'),
              content: TextField(autofocus: true, onSubmitted: (_) => saves++),
              actions: [
                FilledButton(
                  onPressed: () => saves++,
                  child: const Text('Αποθήκευση'),
                ),
              ],
            ),
          ),
          child: const Text('Άνοιγμα'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('το «Χ» με ανοιχτό διάλογο ρωτά, με το όνομα του διαλόγου', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Άνοιγμα'));
    await tester.pumpAndSettle();

    final asking = h.controller.handleUserCloseRequest();
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Υπάρχει ανοιχτό ζήτημα «Επεξεργασία Υπαλλήλου», '
        'θέλετε να το διευθετήσετε;',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Επιστροφή'));
    await tester.pumpAndSettle();
    await asking;

    expect(h.shutdownRuns, 0, reason: 'το «Επιστροφή» δεν κλείνει');
    expect(h.controller.isClosing, isFalse);
    expect(find.text('Αποθήκευση'), findsOneWidget);
  });

  testWidgets('χωρίς ανοιχτό διάλογο το «Χ» κλείνει χωρίς ερώτηση', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());

    await h.controller.handleUserCloseRequest();
    await tester.pump();

    expect(h.shutdownRuns, 1);
    expect(find.text('Κλείσιμο εφαρμογής'), findsNothing);
  });

  testWidgets('μετά το «Κλείσιμο» ούτε κλικ ούτε Enter φτάνουν στον διάλογο', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Άνοιγμα'));
    await tester.pumpAndSettle();

    final asking = h.controller.handleUserCloseRequest();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Κλείσιμο'));
    await tester.pumpAndSettle();
    await asking;
    expect(h.shutdownRuns, 1);

    await tester.tap(find.text('Αποθήκευση'), warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      h.saves,
      0,
      reason: 'καμία ενέργεια χρήστη δεν εκτελείται μέσα στο κλείσιμο',
    );
  });

  testWidgets('το κλείσιμο που έχει ήδη αποφασιστεί δεν ξαναρωτά', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.tap(find.text('Άνοιγμα'));
    await tester.pumpAndSettle();

    // Το αίτημα συναδέλφου, αφού το δέχτηκε ο χρήστης.
    h.controller.handleCloseRequest();
    await tester.pump();

    expect(h.shutdownRuns, 1);
    expect(find.text('Κλείσιμο εφαρμογής'), findsNothing);
    await tester.tap(find.text('Αποθήκευση'), warnIfMissed: false);
    await tester.pump();
    expect(h.saves, 0);
  });

  testWidgets('ο τίτλος διαβάζεται και από το συρόμενο πλαίσιο διαλόγου', (
    tester,
  ) async {
    final tracker = ModalRouteTracker();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [tracker],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DraggableDialogShell(
                title: const Row(
                  children: [Icon(Icons.folder), Text('Επιλογή φακέλου')],
                ),
                builder: (titleHandle) =>
                    AlertDialog(title: titleHandle, content: const Text('…')),
              ),
            ),
            child: const Text('Άνοιγμα'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Άνοιγμα'));
    await tester.pumpAndSettle();

    expect(openDialogTitle(tracker.topDialog!), 'Επιλογή φακέλου');
  });

  test('διάλογος χωρίς τίτλο: η ερώτηση βγαίνει χωρίς όνομα', () {
    expect(
      closeWithOpenDialogMessage(null),
      'Υπάρχει ανοιχτό ζήτημα, θέλετε να το διευθετήσετε;',
    );
  });
}
