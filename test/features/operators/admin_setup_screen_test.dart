// Η οθόνη «Αυτή η βάση δεν έχει διαχειριστή»: τι δείχνει και τι παραδίδει.
//
//   flutter test test/features/operators/admin_setup_screen_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/operators/screens/admin_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Operator _operator(String name) => Operator(
  id: name.length,
  displayName: name,
  createdAt: DateTime(2026, 8, 26),
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<Operator> candidates,
  required Future<String?> Function(Operator) onChoose,
}) => tester.pumpWidget(
  MaterialApp(
    home: AdminSetupScreen(candidates: candidates, onChoose: onChoose),
  ),
);

void main() {
  testWidgets('δείχνει όλα τα ενεργά προφίλ προς επιλογή', (tester) async {
    await _pumpScreen(
      tester,
      candidates: [_operator('Βαρβάρα'), _operator('Παναγιώτης')],
      onChoose: (_) async => null,
    );

    expect(find.text('Βαρβάρα'), findsOneWidget);
    expect(find.text('Παναγιώτης'), findsOneWidget);
  });

  testWidgets('η επιλογή ορίζει τον διαχειριστή μετά από επιβεβαίωση', (
    tester,
  ) async {
    Operator? chosen;
    await _pumpScreen(
      tester,
      candidates: [_operator('Βαρβάρα'), _operator('Παναγιώτης')],
      onChoose: (operator) async {
        chosen = operator;
        return null;
      },
    );

    await tester.tap(find.text('Βαρβάρα'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ορισμός'));
    await tester.pumpAndSettle();

    expect(chosen?.displayName, 'Βαρβάρα');
  });

  testWidgets('η ακύρωση δεν ορίζει κανέναν', (tester) async {
    var called = false;
    await _pumpScreen(
      tester,
      candidates: [_operator('Βαρβάρα')],
      onChoose: (_) async {
        called = true;
        return null;
      },
    );

    await tester.tap(find.text('Βαρβάρα'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Άκυρο'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });

  testWidgets('η αποτυχία του ορισμού λέγεται στον χρήστη', (tester) async {
    await _pumpScreen(
      tester,
      candidates: [_operator('Βαρβάρα')],
      onChoose: (_) async => 'Η βάση είναι κλειδωμένη.',
    );

    await tester.tap(find.text('Βαρβάρα'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ορισμός'));
    await tester.pumpAndSettle();

    expect(find.text('Η βάση είναι κλειδωμένη.'), findsOneWidget);
  });
}
