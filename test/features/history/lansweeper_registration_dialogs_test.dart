// Widget test: dialogs απόφασης καταχώρησης Lansweeper.
//
//   flutter test test/features/history/lansweeper_registration_dialogs_test.dart

import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_registration_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<void> _pumpDialogHost(
  WidgetTester tester, {
  required Future<void> Function(BuildContext context) onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () => onOpen(context),
              child: const Text('Άνοιγμα'),
            );
          },
        ),
      ),
    ),
  );
}

Finder _dialogButton(String label) {
  return find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(label),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Άνοιγμα'));
  await pumpUntilSettled(tester);
}

Future<void> _closeDialogAction(WidgetTester tester, String label) async {
  await tester.tap(_dialogButton(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('showLansweeperResubmitConfirmDialog', () {
    testWidgets('«Συνέχεια» δίνει true', (tester) async {
      bool? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperResubmitConfirmDialog(context);
        },
      );
      await _openDialog(tester);

      expect(find.text('Επαναϋποβολή'), findsOneWidget);
      await tester.tap(find.text('Συνέχεια'));
      await pumpUntilSettled(tester);

      expect(result, isTrue);
    });

    testWidgets('«Άκυρο» δίνει false', (tester) async {
      bool? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperResubmitConfirmDialog(context);
        },
      );
      await _openDialog(tester);

      await tester.tap(find.text('Άκυρο'));
      await pumpUntilSettled(tester);

      expect(result, isFalse);
    });
  });

  group('showLansweeperUnsentTicketChoiceDialog', () {
    testWidgets('εμφανίζει storedTicket και επιστρέφει clear', (tester) async {
      UnsentTicketChoice? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperUnsentTicketChoiceDialog(
            context,
            storedTicket: '17132',
          );
        },
      );
      await _openDialog(tester);

      expect(find.text('Ακαταχώρητη κλήση'), findsOneWidget);
      expect(find.textContaining('#17132'), findsOneWidget);

      await tester.tap(find.text('Μηδενισμός id'));
      await pumpUntilSettled(tester);

      expect(result, UnsentTicketChoice.clear);
    });

    testWidgets('«Διατήρηση id» δίνει retain', (tester) async {
      UnsentTicketChoice? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperUnsentTicketChoiceDialog(
            context,
            storedTicket: '999',
          );
        },
      );
      await _openDialog(tester);

      await tester.tap(find.text('Διατήρηση id'));
      await pumpUntilSettled(tester);

      expect(result, UnsentTicketChoice.retain);
    });

    testWidgets('«Άκυρο» δίνει cancel', (tester) async {
      UnsentTicketChoice? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperUnsentTicketChoiceDialog(
            context,
            storedTicket: '999',
          );
        },
      );
      await _openDialog(tester);

      await tester.tap(find.text('Άκυρο'));
      await pumpUntilSettled(tester);

      expect(result, UnsentTicketChoice.cancel);
    });
  });

  group('showLansweeperDuplicateTicketDialog', () {
    testWidgets('count=1: «άλλη κλήση» και «Πρόσθεση» -> proceed', (tester) async {
      DuplicateTicketAction? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperDuplicateTicketDialog(
            context,
            count: 1,
            ticketId: '555',
          );
        },
      );
      await _openDialog(tester);

      expect(find.text('Ίδιο Ticket ID'), findsOneWidget);
      expect(find.textContaining('1 άλλη κλήση'), findsOneWidget);
      expect(find.textContaining('#555'), findsOneWidget);

      await tester.tap(find.text('Πρόσθεση'));
      await pumpUntilSettled(tester);

      expect(result, DuplicateTicketAction.proceed);
    });

    testWidgets('count=3: «άλλες κλήσεις» και «Αλλαγή id» -> changeId', (tester) async {
      DuplicateTicketAction? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperDuplicateTicketDialog(
            context,
            count: 3,
            ticketId: '777',
          );
        },
      );
      await _openDialog(tester);

      expect(find.textContaining('3 άλλες κλήσεις'), findsOneWidget);

      await tester.tap(find.text('Αλλαγή id'));
      await pumpUntilSettled(tester);

      expect(result, DuplicateTicketAction.changeId);
    });

    testWidgets('«Άκυρο» δίνει cancel', (tester) async {
      DuplicateTicketAction? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperDuplicateTicketDialog(
            context,
            count: 2,
            ticketId: '888',
          );
        },
      );
      await _openDialog(tester);

      await tester.tap(find.text('Άκυρο'));
      await pumpUntilSettled(tester);

      expect(result, DuplicateTicketAction.cancel);
    });
  });

  group('showLansweeperOptionalTicketIdDialog', () {
    testWidgets('εμφανίζει prefilled και subtitle όταν δοθεί', (tester) async {
      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          await showLansweeperOptionalTicketIdDialog(
            context,
            prefilled: '17132',
            title: 'Ticket Lansweeper',
            subtitle: 'Υπότιτλος δοκιμής',
          );
        },
      );
      await _openDialog(tester);

      expect(find.text('Ticket Lansweeper'), findsOneWidget);
      expect(find.text('Υπότιτλος δοκιμής'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '17132',
      );

      await _closeDialogAction(tester, 'Άκυρο');
    });

    testWidgets('«Αποθήκευση» επιστρέφει trimmed ticketId', (tester) async {
      String? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperOptionalTicketIdDialog(
            context,
            prefilled: '',
            title: 'Ticket Lansweeper',
          );
        },
      );
      await _openDialog(tester);

      await tester.enterText(find.byType(TextField), '  17132  ');
      await _closeDialogAction(tester, 'Αποθήκευση');

      expect(result, '17132');
    });

    testWidgets('«Άκυρο» επιστρέφει null', (tester) async {
      String? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperOptionalTicketIdDialog(
            context,
            prefilled: '999',
            title: 'Ticket Lansweeper',
          );
        },
      );
      await _openDialog(tester);

      await _closeDialogAction(tester, 'Άκυρο');

      expect(result, isNull);
    });
  });

  group('showLansweeperManualMarkDialog', () {
    testWidgets('«Αποθήκευση» δίνει trimmed ticketId και raw comment', (tester) async {
      ({String ticketId, String comment})? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperManualMarkDialog(
            context,
            initialTicket: '100',
          );
        },
      );
      await _openDialog(tester);

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '  555  ');
      await tester.enterText(fields.at(1), '  σχόλιο με κενά  ');
      await _closeDialogAction(tester, 'Αποθήκευση');

      expect(result?.ticketId, '555');
      expect(result?.comment, '  σχόλιο με κενά  ');
    });

    testWidgets('«Άκυρο» επιστρέφει null', (tester) async {
      ({String ticketId, String comment})? result;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          result = await showLansweeperManualMarkDialog(
            context,
            initialTicket: '100',
          );
        },
      );
      await _openDialog(tester);

      await _closeDialogAction(tester, 'Άκυρο');

      expect(result, isNull);
    });
  });

  group('showLansweeperFailureReportDialog', () {
    testWidgets('εμφανίζει reportText και «Αντιγραφή αναφοράς» καλεί onCopied', (tester) async {
      var copied = false;
      var completed = false;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          await showLansweeperFailureReportDialog(
            context,
            reportText: 'Αναλυτική αναφορά σφάλματος',
            onCopied: () => copied = true,
          );
          completed = true;
        },
      );
      await _openDialog(tester);

      expect(find.textContaining('Αναλυτική αναφορά σφάλματος'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(_dialogButton('Αντιγραφή αναφοράς'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(copied, isTrue);
      expect(completed, isFalse);
    });

    testWidgets('«Κλείσιμο» ολοκληρώνει το Future', (tester) async {
      var completed = false;

      await _pumpDialogHost(
        tester,
        onOpen: (context) async {
          await showLansweeperFailureReportDialog(
            context,
            reportText: 'Σφάλμα API',
            onCopied: () {},
          );
          completed = true;
        },
      );
      await _openDialog(tester);

      await _closeDialogAction(tester, 'Κλείσιμο');

      expect(completed, isTrue);
    });
  });
}
