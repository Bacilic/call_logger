// Widget tests: ο διάλογος «Το τμήμα είναι σχεδιασμένο στον χάρτη».
//
//   flutter test test/features/directory/screens/widgets/department_floor_change_dialog_test.dart

import 'package:call_logger/features/directory/screens/widgets/department_floor_change_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _kOpenButton = 'OPEN_DIALOG';

Future<void> _pumpHost(
  WidgetTester tester,
  Future<void> Function(BuildContext context) onOpen,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => onOpen(context),
              child: const Text(_kOpenButton),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_kOpenButton));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('κάθε επιλογή δίνει τη δική της έκβαση', (tester) async {
    DepartmentFloorChangeChoice? result;
    var answers = 0;
    await _pumpHost(tester, (context) async {
      result = await showDepartmentFloorChangeDialog(
        context,
        departmentName: 'Μαγειρείο',
        fromFloorLabel: 'Ισόγειο',
        toFloorLabel: '1ος',
      );
      answers++;
    });

    expect(find.textContaining('«Μαγειρείο»'), findsOneWidget);
    expect(find.textContaining('«Ισόγειο»'), findsOneWidget);
    expect(find.textContaining('«1ος»'), findsOneWidget);

    await tester.tap(find.text('Διαγραφή σχεδίασης'));
    await tester.pumpAndSettle();
    expect(result, DepartmentFloorChangeChoice.clearPlacement);

    await tester.tap(find.text(_kOpenButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Μεταφορά σχεδίασης'));
    await tester.pumpAndSettle();
    expect(result, DepartmentFloorChangeChoice.movePlacement);

    await tester.tap(find.text(_kOpenButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Άκυρο'));
    await tester.pumpAndSettle();
    expect(result, isNull, reason: 'η ακύρωση σταματά την αποθήκευση');
    expect(answers, 3);
  });
}
