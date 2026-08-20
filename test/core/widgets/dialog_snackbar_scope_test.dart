// Το τοπικό σύστημα μηνυμάτων διαλόγου δεν καταρρέει ούτε σιωπά ποτέ.
//
// Ολόκληρο αρχείο:
//   flutter test test/core/widgets/dialog_snackbar_scope_test.dart

import 'package:call_logger/core/widgets/dialog_snackbar_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

const _kMessage = 'Υπάρχει ήδη εξοπλισμός με αυτόν τον κωδικό.';
const _kOpenButton = 'ΑΝΟΙΓΜΑ';
const _kShowButton = 'ΕΜΦΑΝΙΣΗ';

/// Διάλογος που τυλίγει σωστά το περιεχόμενό του (η καθιερωμένη χρήση).
class _ScopedDialog extends StatefulWidget {
  const _ScopedDialog();

  @override
  State<_ScopedDialog> createState() => _ScopedDialogState();
}

class _ScopedDialogState extends State<_ScopedDialog> with DialogSnackbarHost {
  @override
  Widget build(BuildContext context) {
    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: AlertDialog(
        content: FilledButton(
          onPressed: () =>
              showDialogSnackBar(const SnackBar(content: Text(_kMessage))),
          child: const Text(_kShowButton),
        ),
      ),
    );
  }
}

/// Διάλογος που δηλώνει σκέτο [ScaffoldMessenger] χωρίς [Scaffold] — η
/// λανθασμένη χρήση που κάποτε έριχνε την εφαρμογή.
class _UnscopedDialog extends StatefulWidget {
  const _UnscopedDialog();

  @override
  State<_UnscopedDialog> createState() => _UnscopedDialogState();
}

class _UnscopedDialogState extends State<_UnscopedDialog>
    with DialogSnackbarHost {
  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: dialogMessengerKey,
      child: AlertDialog(
        content: FilledButton(
          onPressed: () =>
              showDialogSnackBar(const SnackBar(content: Text(_kMessage))),
          child: const Text(_kShowButton),
        ),
      ),
    );
  }
}

Future<void> _openDialogAndShowSnackBar(
  WidgetTester tester,
  WidgetBuilder dialogBuilder,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: dialogBuilder),
              child: const Text(_kOpenButton),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_kOpenButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_kShowButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('showDialogSnackBar — το μήνυμα φτάνει πάντα στον χρήστη', () {
    testWidgets('με DialogSnackbarScope: εμφανίζεται στον τοπικό messenger', (
      tester,
    ) async {
      await _openDialogAndShowSnackBar(tester, (_) => const _ScopedDialog());

      expect(tester.takeException(), isNull);
      expect(
        find.text(_kMessage),
        findsOneWidget,
        reason: greekExpectMsg('Η καθιερωμένη χρήση πρέπει να δείχνει μήνυμα'),
      );
    });

    // Χωρίς την εφεδρεία, αυτή η διάταξη έσκαγε με _AssertionError
    // «no descendant Scaffolds» σε debug — και σε release έχανε το μήνυμα.
    //   flutter test test/core/widgets/dialog_snackbar_scope_test.dart --plain-name "χωρίς Scaffold"
    testWidgets(
      'χωρίς Scaffold: πέφτει στον ριζικό messenger αντί να καταρρεύσει',
      (tester) async {
        await _openDialogAndShowSnackBar(
          tester,
          (_) => const _UnscopedDialog(),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: greekExpectMsg(
            'Ο νεκρός τοπικός messenger δεν πρέπει να ρίχνει την εφαρμογή',
          ),
        );
        expect(
          find.text(_kMessage),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το μήνυμα πρέπει να φτάνει στον χρήστη από τον ριζικό messenger',
          ),
        );
      },
    );

    testWidgets('η εφεδρεία ισχύει και για το μήνυμα με κουμπί αντιγραφής', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _UnscopedDialogWithCopy(),
                  ),
                  child: const Text(_kOpenButton),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(_kOpenButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_kShowButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text(_kMessage), findsOneWidget);
      expect(
        find.byIcon(Icons.content_copy_outlined),
        findsOneWidget,
        reason: greekExpectMsg(
          'Το κουμπί αντιγραφής επιβιώνει και στη διαδρομή εφεδρείας',
        ),
      );
    });
  });

  // Το μήνυμα με αντιγραφή δεν εμφανίζεται όπως το έστειλε ο καλών: χτίζεται
  // εκ νέου για να χωρέσει το κουμπί. Όσο το αντίγραφο κρατούσε μόνο διάρκεια
  // και συμπεριφορά, κάθε άλλη ρύθμιση έσβηνε σιωπηλά — χωρίς παράπονο από τον
  // μεταγλωττιστή, με το snackbar να εμφανίζεται κανονικά και λάθος.
  //   flutter test test/core/widgets/dialog_snackbar_scope_test.dart --plain-name "ρυθμίσεις"
  testWidgets('οι ρυθμίσεις του καλούντος επιβιώνουν στην αντιγραφή', (
    tester,
  ) async {
    await _openDialogAndShowSnackBar(
      tester,
      (_) => const _ScopedDialogWithStyledCopy(),
    );

    final shown = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(
      shown.backgroundColor,
      _kStyledBackground,
      reason: greekExpectMsg(
        'Το χρώμα που ζήτησε ο καλών δεν επιτρέπεται να χαθεί επειδή ζητήθηκε '
        'και αντιγραφή',
      ),
    );
    expect(shown.duration, const Duration(seconds: 8));
    expect(shown.behavior, SnackBarBehavior.floating);
    expect(shown.showCloseIcon, isTrue);
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
    expect(find.text(_kMessage), findsOneWidget);
  });
}

const Color _kStyledBackground = Color(0xFF7B1FA2);

/// Διάλογος που στέλνει ρυθμισμένο snackbar **και** ζητά αντιγραφή — ο
/// συνδυασμός που έχανε τις ρυθμίσεις.
class _ScopedDialogWithStyledCopy extends StatefulWidget {
  const _ScopedDialogWithStyledCopy();

  @override
  State<_ScopedDialogWithStyledCopy> createState() =>
      _ScopedDialogWithStyledCopyState();
}

class _ScopedDialogWithStyledCopyState
    extends State<_ScopedDialogWithStyledCopy>
    with DialogSnackbarHost {
  @override
  Widget build(BuildContext context) {
    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: AlertDialog(
        content: FilledButton(
          onPressed: () => showDialogSnackBar(
            const SnackBar(
              content: Text(_kMessage),
              backgroundColor: _kStyledBackground,
              duration: Duration(seconds: 8),
              behavior: SnackBarBehavior.floating,
              showCloseIcon: true,
            ),
            copyText: 'τεχνικές λεπτομέρειες',
          ),
          child: const Text(_kShowButton),
        ),
      ),
    );
  }
}

class _UnscopedDialogWithCopy extends StatefulWidget {
  const _UnscopedDialogWithCopy();

  @override
  State<_UnscopedDialogWithCopy> createState() =>
      _UnscopedDialogWithCopyState();
}

class _UnscopedDialogWithCopyState extends State<_UnscopedDialogWithCopy>
    with DialogSnackbarHost {
  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: dialogMessengerKey,
      child: AlertDialog(
        content: FilledButton(
          onPressed: () => showDialogSnackBar(
            const SnackBar(content: Text(_kMessage)),
            copyText: 'τεχνικές λεπτομέρειες',
          ),
          child: const Text(_kShowButton),
        ),
      ),
    );
  }
}
