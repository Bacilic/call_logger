// Widget tests: «Αναίρεση» στη διαγραφή κλήσης από το Ιστορικό Κλήσεων.
//
//   flutter test test/features/history/call_delete_undo_test.dart

import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:call_logger/features/history/widgets/call_delete_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Αναίρεση διαγραφής κλήσης', () {
    Future<int> seedCall(WidgetTester tester) async {
      final callId = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        return CallsRepository(db).insertCall(
          CallModel(
            phoneText: kTestPhoneDigits,
            issue: 'Δοκιμή αναίρεσης διαγραφής',
            status: 'completed',
          ),
        );
      });
      return callId!;
    }

    Future<int?> isDeletedFlag(WidgetTester tester, int callId) async {
      return tester.runAsync<int?>(() async {
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query(
          'calls',
          columns: ['is_deleted'],
          where: 'id = ?',
          whereArgs: [callId],
        );
        if (rows.isEmpty) return null;
        final value = rows.first['is_deleted'];
        return value is int ? value : int.tryParse(value?.toString() ?? '');
      });
    }

    Future<void> openDeleteDialogAndConfirm(
      WidgetTester tester,
      int callId,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        showCallDeleteDialog(context, callId: callId),
                    child: const Text('Άνοιγμα διαλόγου'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Άνοιγμα διαλόγου'));
      await pumpUntilSettled(tester);

      // Η κλήση δεν έχει εκκρεμότητες → απλό κουμπί διαγραφής. Ο τίτλος του
      // διαλόγου έχει το ίδιο κείμενο, οπότε στοχεύουμε ρητά το κουμπί — και
      // περιμένουμε την async φόρτωση συνδέσεων (πραγματικό I/O βάσης).
      final deleteButton = find.widgetWithText(FilledButton, 'Διαγραφή κλήσης');
      for (var i = 0; i < 40 && !tester.any(deleteButton); i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      expect(deleteButton, findsOneWidget);

      await tester.tap(deleteButton);
      await pumpUntilSettled(tester);
    }

    String countdownText(WidgetTester tester) =>
        tester.widget<Text>(find.textContaining('θα διαγραφεί σε')).data!;

    testWidgets(
      'το snackbar λέει την αλήθεια: «θα διαγραφεί σε Ν″» με ζωντανή μέτρηση',
      (tester) async {
        final callId = await seedCall(tester);
        await openDeleteDialogAndConfirm(tester, callId);

        // Μήνυμα μέλλοντος — όχι «διαγράφηκε» για κάτι που δεν έχει συμβεί.
        expect(find.textContaining('θα διαγραφεί σε'), findsOneWidget);
        expect(find.textContaining('διαγράφηκε επιτυχώς'), findsNothing);

        // Η μέτρηση προχωρά: το κείμενο αλλάζει από δευτερόλεπτο σε δευτερόλεπτο.
        final before = countdownText(tester);
        await tester.pump(const Duration(seconds: 1));
        final after = countdownText(tester);
        expect(after, isNot(before));

        // Κλείσιμο ιστορίας: αναίρεση + λήξη snackbars, να μη μείνουν timers.
        await tester.tap(find.text('Αναίρεση'));
        await pumpUntilSettled(tester);
        await tester.pump(const Duration(seconds: 6));
      },
    );

    testWidgets(
      'πάτημα «Αναίρεση» εντός του παραθύρου → η κλήση παραμένει στη βάση',
      (tester) async {
        final callId = await seedCall(tester);
        await openDeleteDialogAndConfirm(tester, callId);

        // Το snackbar προσφέρει «Αναίρεση» — η βάση δεν έχει αγγιχτεί ακόμη.
        expect(find.text('Αναίρεση'), findsOneWidget);
        expect(await isDeletedFlag(tester, callId), 0);

        await tester.tap(find.text('Αναίρεση'));
        await pumpUntilSettled(tester);
        expect(find.text('Η διαγραφή αναιρέθηκε.'), findsOneWidget);
        expect(find.textContaining('θα διαγραφεί σε'), findsNothing);

        // Ακόμη και μετά τη λήξη του παραθύρου, τίποτα δεν εκτελείται.
        await tester.pump(const Duration(seconds: 6));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        expect(await isDeletedFlag(tester, callId), 0);
      },
    );

    testWidgets(
      'χωρίς αναίρεση → στη λήξη η κλήση διαγράφεται ΚΑΙ η προσφορά «Αναίρεση» κλείνει αμέσως',
      (tester) async {
        final callId = await seedCall(tester);
        await openDeleteDialogAndConfirm(tester, callId);

        expect(await isDeletedFlag(tester, callId), 0);

        await tester.pump(const Duration(seconds: 6));
        // Η ολοκλήρωση της διαγραφής διασχίζει πολλά σκαλιά πραγματικού
        // async (FFI βάσης) και frames (postFrame ανανέωσης) εναλλάξ —
        // αντλούμε επαναληπτικά μέχρι να στραγγίξει όλη η αλυσίδα.
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
          });
          await tester.pump(const Duration(milliseconds: 60));
        }
        await pumpUntilSettled(tester);

        expect(await isDeletedFlag(tester, callId), 1);

        // Το snackbar της μέτρησης έχει τεράστιο δικό του duration — αν η
        // «Αναίρεση» λείπει, την έκλεισε ενεργά ο δρομέας κατά την εκτέλεση.
        expect(find.text('Αναίρεση'), findsNothing);
        expect(find.textContaining('θα διαγραφεί σε'), findsNothing);
        expect(find.text('Η κλήση διαγράφηκε.'), findsOneWidget);

        // Λήξη του snackbar επιβεβαίωσης, να μη μείνει εκκρεμής timer.
        await tester.pump(const Duration(seconds: 6));
      },
    );
  });

  group('Μαζική διαγραφή: η επιλογή των κλήσεων', () {
    // Δύο κλήσεις τσεκαρισμένες, ανοίγει ο διάλογος μαζικής διαγραφής.
    // Επιστρέφει το container για να διαβάζει το τεστ την επιλογή.
    Future<ProviderContainer> openBulkDialogWithSelection(
      WidgetTester tester,
    ) async {
      final ids = await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final repo = CallsRepository(db);
        return <int>[
          for (var i = 0; i < 2; i++)
            await repo.insertCall(
              CallModel(
                phoneText: kTestPhoneDigits,
                issue: 'Μαζική διαγραφή $i',
                status: 'completed',
              ),
            ),
        ];
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Η επιλογή ζει όσο την παρακολουθεί κάποιος, όπως η οθόνη Ιστορικού.
      container.listen(historySelectedCallIdsProvider, (_, _) {});
      container
          .read(historySelectedCallIdsProvider.notifier)
          .setAll(ids!.toSet());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        showCallBulkDeleteDialog(context, callIds: ids),
                    child: const Text('Άνοιγμα διαλόγου'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Άνοιγμα διαλόγου'));
      await pumpUntilSettled(tester);

      // Περιμένουμε την async φόρτωση συνδέσεων (πραγματικό I/O βάσης).
      final cancel = find.widgetWithText(TextButton, 'Ακύρωση');
      for (var i = 0; i < 40 && !tester.any(cancel); i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      expect(cancel, findsOneWidget);
      return container;
    }

    testWidgets('«Ακύρωση» στον διάλογο → οι κλήσεις μένουν τσεκαρισμένες', (
      tester,
    ) async {
      final container = await openBulkDialogWithSelection(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Ακύρωση'));
      await pumpUntilSettled(tester);

      expect(find.text('Μαζική διαγραφή κλήσεων'), findsNothing);
      expect(container.read(historySelectedCallIdsProvider), hasLength(2));
    });

    testWidgets('επιβεβαίωση διαγραφής → η επιλογή καθαρίζει', (tester) async {
      final container = await openBulkDialogWithSelection(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Μαζική διαγραφή'));
      await pumpUntilSettled(tester);

      expect(container.read(historySelectedCallIdsProvider), isEmpty);

      // Κλείσιμο ιστορίας: αναίρεση + λήξη snackbars, να μη μείνουν timers.
      await tester.tap(find.text('Αναίρεση'));
      await pumpUntilSettled(tester);
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
