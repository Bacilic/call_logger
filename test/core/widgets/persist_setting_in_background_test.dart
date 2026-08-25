// Οι αλλαγές ρυθμίσεων φεύγουν χωρίς να τις περιμένει κανείς, ώστε η διεπαφή να
// μη «κολλάει» όσο γράφει η δικτυακή βάση. Αυτό όμως κατάπινε και την αποτυχία:
// η ρύθμιση δεν σωζόταν, κανένα μήνυμα δεν εμφανιζόταν, και η οθόνη συνέχιζε να
// δείχνει τη νέα τιμή.
//
//   flutter test test/core/widgets/persist_setting_in_background_test.dart

import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/widgets/database_persistence_error_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpHost(
  WidgetTester tester,
  void Function(BuildContext context) onTap,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => onTap(context),
              child: const Text('Άλλαξε ρύθμιση'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('persistSettingInBackground', () {
    testWidgets('η επιτυχής αποθήκευση δεν ενοχλεί με μήνυμα', (tester) async {
      await _pumpHost(
        tester,
        (context) => persistSettingInBackground(context, Future<void>.value()),
      );

      await tester.tap(find.text('Άλλαξε ρύθμιση'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('η αποτυχία εγγραφής φτάνει στον χρήστη', (tester) async {
      await _pumpHost(
        tester,
        (context) => persistSettingInBackground(
          context,
          Future<void>.error(
            const FileSystemException('Ο φάκελος δεν είναι προσβάσιμος'),
            StackTrace.empty,
          ),
        ),
      );

      await tester.tap(find.text('Άλλαξε ρύθμιση'));
      await tester.pumpAndSettle();

      expect(
        find.byType(SnackBar),
        findsOneWidget,
        reason: 'ό,τι δεν γράφτηκε το μαθαίνει ο χρήστης',
      );
    });

    testWidgets('η διεπαφή δεν περιμένει την εγγραφή', (tester) async {
      final completer = Completer<void>();
      await _pumpHost(
        tester,
        (context) => persistSettingInBackground(context, completer.future),
      );

      await tester.tap(find.text('Άλλαξε ρύθμιση'));
      await tester.pump();

      // Το κουμπί απαντά κανονικά όσο η εγγραφή είναι ακόμη σε εξέλιξη.
      expect(find.text('Άλλαξε ρύθμιση'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('οθόνη που έκλεισε δεν προσπαθεί να μιλήσει', (tester) async {
      late BuildContext captured;
      await _pumpHost(tester, (context) => captured = context);
      await tester.tap(find.text('Άλλαξε ρύθμιση'));
      await tester.pump();

      final completer = Completer<void>();
      persistSettingInBackground(captured, completer.future);

      // Η οθόνη φεύγει πριν απαντήσει η βάση.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      completer.completeError(
        const FileSystemException('πολύ αργά'),
        StackTrace.empty,
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
