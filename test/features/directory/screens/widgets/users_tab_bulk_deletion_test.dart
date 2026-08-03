// Μαζική διαγραφή υπαλλήλων από την καρτέλα: τι μένει επιλεγμένο μετά.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/users_tab_bulk_deletion_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/users_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_setup.dart';

class _FakeDirectoryNotifier extends DirectoryNotifier {
  _FakeDirectoryNotifier(this._initialState);

  final DirectoryState _initialState;

  @override
  DirectoryState build() => _initialState;

  @override
  Future<void> loadUsers() async {}
}

/// Περιμένει να εμφανιστεί κάτι που εξαρτάται από αναγνώσεις της βάσης.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  testWidgets(
    'όποιον αφαιρέσει ο χρήστης από την προεπισκόπηση μένει επιλεγμένος',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const keptId = 9101;
      const deletedId = 9102;
      final kept = UserModel(
        id: keptId,
        firstName: 'Μένει',
        lastName: 'Επιλεγμένος',
      );
      final deleted = UserModel(
        id: deletedId,
        firstName: 'Φεύγει',
        lastName: 'Τώρα',
      );
      final initial = DirectoryState(
        allUsers: [kept, deleted],
        filteredUsers: [kept, deleted],
        selectedIds: {keptId, deletedId},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...callLoggerTestProviderOverrides(),
            directoryProvider.overrideWith(
              () => _FakeDirectoryNotifier(initial),
            ),
            catalogUsersContinuousScrollProvider.overrideWith(
              (ref) async => true,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: UsersTab())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Διαγραφή'));
      await _pumpUntil(tester, find.byType(AlertDialog));

      // Αφαίρεση του ενός από τη λίστα — «αυτόν αργότερα», όχι «αυτόν ποτέ».
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Μένει Επιλεγμένος'),
            matching: find.byType(Card),
          ),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Διαγραφή'),
        ),
      );
      await _pumpUntil(tester, find.byType(SnackBar));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(UsersTab)),
      );
      expect(container.read(directoryProvider).selectedIds, {keptId});

      await flushCallLoggerSqfliteLockTimers(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('με τη διέξοδο της διακοπής διαγράφονται μόνο οι ολοκληρωμένοι', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late int doneId;
    late int abortedId;
    await tester.runAsync(() async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('users');

      doneId = await db.insert('users', {
        'first_name': 'Χωρίς',
        'last_name': 'Στοιχεία',
        'is_deleted': 0,
      });
      abortedId = await db.insert('users', {
        'first_name': 'Με',
        'last_name': 'Τηλέφωνο',
        'is_deleted': 0,
      });
      // Προσωπικό τηλέφωνο ΜΟΝΟ στον δεύτερο: εκεί ανοίγει διάλογος και εκεί
      // διακόπτει ο χρήστης. Ο πρώτος ολοκληρώνεται σιωπηλά.
      final phoneId = await db.insert('phones', {
        'number': '2901',
        'is_deleted': 0,
      });
      await db.insert('user_phones', {
        'user_id': abortedId,
        'phone_id': phoneId,
      });
    });

    final done = UserModel(
      id: doneId,
      firstName: 'Χωρίς',
      lastName: 'Στοιχεία',
    );
    final aborted = UserModel(
      id: abortedId,
      firstName: 'Με',
      lastName: 'Τηλέφωνο',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...callLoggerTestProviderOverrides(),
          directoryProvider.overrideWith(
            () => _FakeDirectoryNotifier(
              DirectoryState(
                allUsers: [done, aborted],
                filteredUsers: [done, aborted],
                selectedIds: {doneId, abortedId},
              ),
            ),
          ),
          catalogUsersContinuousScrollProvider.overrideWith(
            (ref) async => true,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: UsersTab())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Διαγραφή'));
    await _pumpUntil(tester, find.byType(AlertDialog));

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Διαγραφή'),
      ),
    );
    // Ο πρώτος περνά χωρίς ερώτηση· ο δεύτερος ανοίγει τη ροή αποδέσμευσης.
    await _pumpUntil(tester, find.text('Ακύρωση'));
    await tester.tap(find.text('Ακύρωση'));
    await _pumpUntil(tester, find.text('Διακοπή διαδικασίας;'));

    // Η απόφαση παίρνεται εδώ, σε ΕΝΑΝ διάλογο — και το κείμενο δεν υπόσχεται
    // απώλεια που δεν θα συμβεί.
    expect(
      find.textContaining('Ολοκληρώσατε 1 υπάλληλο από τους 2.'),
      findsOneWidget,
    );
    expect(find.textContaining('θα χαθ'), findsNothing);
    // Η εξήγηση του κουμπιού ανήκει στην υπόδειξή του, όχι στο σώμα.
    expect(find.textContaining('Κλείνει ο οδηγός'), findsNothing);

    await tester.tap(find.text('Εφαρμογή απαντήσεων'));
    await _pumpUntil(tester, find.byType(SnackBar));

    final snackBar = find.byType(SnackBar);
    expect(snackBar, findsOneWidget);
    expect(
      find.descendant(
        of: snackBar,
        matching: find.textContaining('Χωρίς Στοιχεία'),
      ),
      findsOneWidget,
    );
    // Ο υπάλληλος όπου διακόπηκε η ροή ΔΕΝ διαγράφηκε.
    expect(
      find.descendant(
        of: snackBar,
        matching: find.textContaining('Με Τηλέφωνο'),
      ),
      findsNothing,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(UsersTab)),
    );
    expect(container.read(directoryProvider).selectedIds, {abortedId});

    await flushCallLoggerSqfliteLockTimers(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
