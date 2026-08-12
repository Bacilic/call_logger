// Ο έλεγχος «Μήπως εννοείτε;» τρέχει μόνο όταν το ονοματεπώνυμο είναι
// καινούριο ή άλλαξε — δύο συνώνυμοι υπάλληλοι δεν ξαναρωτιούνται σε κάθε
// αποθήκευση οποιουδήποτε άλλου πεδίου.
//
//   flutter test test/features/directory/user_form_similar_name_guard_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/user_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kSurname = 'Αναγνωστοπούλου';
const _kEditedFirstName = 'Βάσω';
const _kNamesakeFirstName = 'Θάνια';
const _kOpenButton = 'OPEN_USER_FORM';
const _kEditTitle = 'Επεξεργασία Υπαλλήλου';
const _kSimilarDialogTitle = 'Μήπως εννοείτε;';
const _kIdenticalDialogTitle = 'Ίδιο ονοματεπώνυμο';

Finder _fieldByLabel(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is InputDecorator && w.decoration.labelText == label,
  ),
  matching: find.byType(EditableText),
);

/// Δύο υπάλληλοι με το ίδιο επώνυμο — η κατάσταση που ήδη υπάρχει στη βάση
/// του χρήστη και έχει ήδη κριθεί αποδεκτή.
///
/// Γράφει ΜΟΝΟ στη βάση: τη φόρτωση του καταλόγου την κάνει ο
/// `lookupServiceProvider`, οπότε το seed πρέπει να προηγείται του πρώτου
/// `read`. Δεύτερη φόρτωση εδώ αφήνει εκκρεμή timer της sqflite στον
/// εικονικό χρόνο του widget test.
Future<void> _seedNamesakes() async {
  final db = await DatabaseHelper.instance.database;
  // Ίδια αφετηρία σε κάθε τεστ: ένα υπόλειμμα από προηγούμενο τεστ μπαίνει
  // στα ταιριάσματα με score κάτω από 100 (κοινό επώνυμο, άλλο όνομα) και
  // γυρίζει τον τίτλο από «Ίδιο ονοματεπώνυμο» σε «Μήπως εννοείτε;».
  await db.delete('users', where: 'last_name = ?', whereArgs: [_kSurname]);
  for (final firstName in <String>[_kNamesakeFirstName, _kEditedFirstName]) {
    await db.insert('users', {
      'first_name': firstName,
      'last_name': _kSurname,
      'is_deleted': 0,
    });
  }
}

Future<void> _openEditForm(
  WidgetTester tester,
  ProviderContainer container, {
  required UserModel user,
  required DirectoryNotifier notifier,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: true,
                  builder: (ctx) =>
                      UserFormDialog(initialUser: user, notifier: notifier),
                ),
                child: const Text(_kOpenButton),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_kOpenButton));
  await pumpUntilSettledLong(tester);
}

/// Η αποθήκευση ρωτά τη βάση, και ο εικονικός χρόνος του widget test δεν κινεί
/// τίποτα εκτός Dart. Χρειάζεται πραγματικός χρόνος ανάμεσα στα pump, αλλιώς
/// το τεστ σκάει με «A Timer is still pending».
///
/// Σταματά μόλις κριθεί η αποθήκευση με οποιονδήποτε από τους δύο τρόπους:
/// έκλεισε η φόρμα, ή μπήκε μπροστά διάλογος που περιμένει απόφαση.
Future<void> _pumpUntilSaveResolves(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final formClosed = find.text(_kEditTitle).evaluate().isEmpty;
    final dialogUp =
        find.text(_kSimilarDialogTitle).evaluate().isNotEmpty ||
        find.text(_kIdenticalDialogTitle).evaluate().isNotEmpty;
    if (formClosed || dialogUp) return;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Φρουρός ομοιότητας ονόματος στη φόρμα υπαλλήλου', () {
    testWidgets(
      'επεξεργασία που δεν αγγίζει το όνομα δεν ρωτά για συνώνυμο υπάλληλο',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DirectoryNotifier notifier;
        late UserModel edited;
        await tester.runAsync(() async {
          await _seedNamesakes();
          await container.read(lookupServiceProvider.future);
          notifier = container.read(directoryProvider.notifier);
          await notifier.loadUsers();
          edited = notifier.allUsersForUi.firstWhere(
            (u) =>
                u.firstName == _kEditedFirstName && u.lastName == _kSurname,
          );
          await _openEditForm(
            tester,
            container,
            user: edited,
            notifier: notifier,
          );
        });

        expect(find.text(_kEditTitle), findsOneWidget);

        await tester.enterText(_fieldByLabel('Σημειώσεις'), 'άσχετη αλλαγή');
        await pumpUntilSettled(tester);

        await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
        await _pumpUntilSaveResolves(tester);

        expect(
          find.text(_kSimilarDialogTitle),
          findsNothing,
          reason: greekExpectMsg(
            'Το ονοματεπώνυμο δεν άλλαξε — η συνωνυμία έχει ήδη κριθεί '
            'αποδεκτή και δεν ξανακρίνεται σε κάθε αποθήκευση',
          ),
        );
        expect(find.text(_kIdenticalDialogTitle), findsNothing);
      },
    );

    testWidgets(
      'μετονομασία πάνω σε συνώνυμο ρωτά, χωρίς να μιλά για νέα εγγραφή',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late DirectoryNotifier notifier;
        late UserModel edited;
        await tester.runAsync(() async {
          await _seedNamesakes();
          await container.read(lookupServiceProvider.future);
          notifier = container.read(directoryProvider.notifier);
          await notifier.loadUsers();
          edited = notifier.allUsersForUi.firstWhere(
            (u) =>
                u.firstName == _kEditedFirstName && u.lastName == _kSurname,
          );
          await _openEditForm(
            tester,
            container,
            user: edited,
            notifier: notifier,
          );
        });

        await tester.enterText(_fieldByLabel('Όνομα'), _kNamesakeFirstName);
        await pumpUntilSettled(tester);

        await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
        await _pumpUntilSaveResolves(tester);

        expect(
          find.text(_kIdenticalDialogTitle),
          findsOneWidget,
          reason: greekExpectMsg(
            'Η μετονομασία σε υπάρχον ονοματεπώνυμο γεννά τον κίνδυνο τώρα, '
            'άρα η προειδοποίηση οφείλει να εμφανιστεί',
          ),
        );
        expect(
          find.textContaining('νέα εγγραφή'),
          findsNothing,
          reason: greekExpectMsg(
            'Η μετονομασία δεν δημιουργεί εγγραφή — ο χρήστης θα έψαχνε μια '
            'εγγραφή που δεν έγινε ποτέ',
          ),
        );
        expect(find.text('Ναι, συνέχισε τη μετονομασία'), findsOneWidget);
      },
    );
  });
}
