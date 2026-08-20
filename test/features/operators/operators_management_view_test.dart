// Η οθόνη «Χρήστες»: η αποθήκευση φτάνει ως τη λίστα, και η μπλοκαρισμένη
// αποθήκευση κρατά τον διάλογο ανοιχτό με τον λόγο.
//
//   flutter test test/features/operators/operators_management_view_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/operators/screens/operators_management_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Προωθεί μαζί **πραγματικό I/O** και **κινούμενα σχέδια**.
///
/// Χωρίς `runAsync` δεν προχωρά η βάση (ο ψεύτικος χρόνος δεν κινεί τίποτα
/// εκτός Dart)· και `pumpAndSettle` απαγορεύεται εδώ, γιατί ο δείκτης φόρτωσης
/// γυρίζει για πάντα και η αναμονή δεν τελειώνει ποτέ.
Future<void> _advance(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  group('Οθόνη «Χρήστες»', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('operators_view_test_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/operators.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await db.delete('operators');
      CurrentOperator.reset();
    });

    tearDownAll(() async {
      CurrentOperator.reset();
      await releaseCallLoggerTestDatabase();
    });

    /// Ανοίγει τη φόρμα του συγκεκριμένου προφίλ — όχι «της πρώτης γραμμής».
    ///
    /// Η σειρά της λίστας είναι αλφαβητική· ένα τεστ που δείχνει σε θέση αντί
    /// για όνομα αλλάζει νόημα μόλις αλλάξουν τα δεδομένα.
    Future<void> openEditorOf(WidgetTester tester, String displayName) async {
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Card, displayName),
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await _advance(tester);
    }

    testWidgets('η μετονομασία φτάνει ως τη λίστα', (tester) async {
      // Κάθε εγγραφή στη βάση θέλει runAsync: μέσα στο testWidgets ο χρόνος
      // είναι ψεύτικος και δεν κινεί τίποτα εκτός Dart — ούτε το FFI της
      // SQLite. Χωρίς αυτό, το τεστ δεν αποτυγχάνει· κρεμάει.
      await tester.runAsync(() async {
        await OperatorRepository(db).insert(
          Operator(
            displayName: 'v.drosos',
            windowsAccount: 'v.drosos',
            isAdmin: true,
            createdAt: DateTime(2026, 8, 19),
          ),
        );
      });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OperatorsManagementView())),
      );
      await _advance(tester);
      expect(find.text('v.drosos'), findsWidgets);

      await openEditorOf(tester, 'v.drosos');
      await tester.enterText(find.byType(TextField).first, 'Βασίλης Δρόσος');
      await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
      await _advance(tester);

      expect(find.text('Βασίλης Δρόσος'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Αποθήκευση'),
        findsNothing,
        reason: 'ο διάλογος οφείλει να έχει κλείσει μετά από επιτυχή αποθήκευση',
      );
    });

    testWidgets('μπλοκαρισμένη αποθήκευση: ο διάλογος μένει με τον λόγο', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final repository = OperatorRepository(db);
        await repository.insert(
          Operator(displayName: 'Πρώτος', createdAt: DateTime(2026, 8, 19)),
        );
        await repository.insert(
          Operator(displayName: 'Δεύτερος', createdAt: DateTime(2026, 8, 19)),
        );
      });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OperatorsManagementView())),
      );
      await _advance(tester);

      await openEditorOf(tester, 'Δεύτερος');
      await tester.enterText(find.byType(TextField).first, 'Πρώτος');
      await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
      await _advance(tester);

      expect(find.textContaining('Υπάρχει ήδη'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Αποθήκευση'),
        findsOneWidget,
        reason: 'ο διάλογος δεν κλείνει όταν η αποθήκευση δεν επιτράπηκε',
      );

      // Κλείσιμο του διαλόγου: αφημένος ανοιχτός, τα πεδία του δεν προλαβαίνουν
      // να απελευθερωθούν και ο ανιχνευτής διαρροών το αναφέρει.
      await tester.tap(find.widgetWithText(TextButton, 'Ακύρωση'));
      await _advance(tester, rounds: 4);
    });
  });
}
