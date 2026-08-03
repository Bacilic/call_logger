// Ο διάλογος επιβεβαίωσης διαγραφής μετακινείται, ώστε να φαίνονται τα
// δεδομένα από πίσω πριν την απόφαση.
//
//   flutter test test/features/directory/shared_asset_disconnect_delete_confirm_test.dart --timeout 30s

import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

const _deptName = 'Πληροφορική';
const _phone = '2854';

final _departments = <DepartmentModel>[DepartmentModel(id: 1, name: _deptName)];

/// Σταθερές συνδέσεις, χωρίς πραγματική βάση.
Future<List<String>> _references({
  required bool isPhone,
  required String value,
}) async => const <String>['Βασίλης Δρόσος', _deptName, '2 εκκρεμότητες'];

Future<AssetHistoryLinks> _noHistory(AssetDisconnectItem item) async =>
    const AssetHistoryLinks();

/// Ανοίγει τη ροή και φτάνει ως τον διάλογο επιβεβαίωσης διαγραφής.
Future<void> _openDeleteConfirmation(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showSharedAssetDisconnectFlow(
              context: context,
              sourceDepartmentId: 1,
              sourceDepartmentName: _deptName,
              phones: const [_phone],
              availableDepartments: _departments,
              mode: SharedAssetDisconnectMode.personalPhone,
              personalPhoneUserDisplayName: 'Βασίλης Δρόσος',
              referenceLookup: _references,
              historyLookup: _noHistory,
            ),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Διαγραφή'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('το σύρσιμο από τον τίτλο μετακινεί τον διάλογο διαγραφής', (
    tester,
  ) async {
    await _openDeleteConfirmation(tester);

    expect(
      find.text('Διαγραφή τηλεφώνου'),
      findsOneWidget,
      reason: greekExpectMsg(
        'Η επιλογή «Διαγραφή» πρέπει να ανοίγει τον διάλογο επιβεβαίωσης',
      ),
    );

    final title = find.text('Διαγραφή τηλεφώνου');
    final before = tester.getTopLeft(title);

    const delta = Offset(60, 40);
    await tester.drag(title, delta);
    await tester.pump();

    final after = tester.getTopLeft(title);
    expect(
      after - before,
      delta,
      reason: greekExpectMsg(
        'Ο διάλογος επιβεβαίωσης διαγραφής πρέπει να μετακινείται με σύρσιμο '
        'από τον τίτλο, ώστε να φαίνονται τα δεδομένα από πίσω',
      ),
    );
  });
}
