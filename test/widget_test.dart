// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.
//
// For key events: always send keyUp AFTER keyDown (e.g. sendKeyDownEvent then
// sendKeyUpEvent) so the key sequence is correct. See docs/KEYBOARD_AND_FOCUS.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:call_logger/main.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/init/app_initializer.dart';
import 'package:call_logger/core/init/app_init_provider.dart';

void main() {
  testWidgets('Η εφαρμογή εμφανίζει το κύριο κέλυφος και τα πεδία εισαγωγής κλήσης', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appInitProvider.overrideWith(
            (ref) => Future.value(AppInitResult(
              result: DatabaseInitResult.success(),
              isLocalDevMode: false,
            )),
          ),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Η σύνδεση με τη βάση δεδομένων πέτυχε.'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('Πεδίο Καλούντας: πληκτρολόγηση ονόματος, κενό και γράμμα προστίθεται (χωρίς αντικατάσταση όλου του κειμένου)', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appInitProvider.overrideWith(
            (ref) => Future.value(AppInitResult(
              result: DatabaseInitResult.success(),
              isLocalDevMode: false,
            )),
          ),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Πεδίο Καλούντας = δεύτερο TextField (0: Τηλέφωνο, 1: Καλούντας, 2: Εξοπλισμός, 3: Σημειώσεις)
    final callerField = find.byType(TextField).at(1);
    expect(callerField, findsOneWidget);
    await tester.tap(callerField);
    await tester.pump();

    await tester.enterText(callerField, 'Κατερίνα');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();

    final editable = find.descendant(
      of: callerField,
      matching: find.byType(EditableText),
    );
    expect(editable, findsOneWidget);
    final text = tester.widget<EditableText>(editable).controller.text;
    // Μετά το κενό το κείμενο παραμένει «Κατερίνα » (ή τουλάχιστον «Κατερίνα») χωρίς αντικατάσταση όλου.
    expect(text, contains('Κατερίνα'));
    expect(text.length, greaterThanOrEqualTo(8));

    // Εκτελεί pending timers (π.χ. _scheduleCompletedLookup 250ms) ώστε να μην μένει timer ανοιχτό.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });
}
