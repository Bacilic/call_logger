// Ο επιλογέας προορισμού δεν αφήνει να περάσει τμήμα που διαγράφεται — ούτε με
// επιλογή από τη λίστα, ούτε με πληκτρολόγηση.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/screens/widgets/asset_transfer_target_blocked_test.dart

import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/screens/widgets/asset_transfer_target_dialog.dart';
import 'package:call_logger/features/directory/services/asset_disconnect_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DepartmentModel _dept(int id, String name) =>
    DepartmentModel(id: id, name: name);

void main() {
  SharedAssetTransferTarget? captured;
  var closed = false;

  Future<void> openPicker(
    WidgetTester tester, {
    required List<DepartmentModel> available,
    List<String> blocked = const [],
  }) async {
    captured = null;
    closed = false;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                captured = await showAssetTransferTargetPicker(
                  context: ctx,
                  headerLabel: 'Πού μεταφέρονται όλα;',
                  availableDepartments: available,
                  blockedDepartmentNames: blocked,
                );
                closed = true;
              },
              child: const Text('άνοιγμα'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('άνοιγμα'));
    await tester.pumpAndSettle();
  }

  testWidgets('όνομα τμήματος που διαγράφεται: μήνυμα και ανενεργό κουμπί', (
    tester,
  ) async {
    await openPicker(
      tester,
      available: [_dept(1, 'Πληροφορική')],
      blocked: const ['Δοκιμαστικό'],
    );

    await tester.enterText(find.byType(TextField), 'Δοκιμαστικό');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('διαγράφεται σε αυτή την πράξη'),
      findsOneWidget,
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Μεταφορά'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('δεν προτείνεται καν «δημιουργία νέου» για απαγορευμένο όνομα', (
    tester,
  ) async {
    await openPicker(
      tester,
      available: [_dept(1, 'Πληροφορική')],
      blocked: const ['Δοκιμαστικό'],
    );

    await tester.enterText(find.byType(TextField), 'Δοκιμαστικό');
    await tester.pumpAndSettle();

    expect(find.textContaining('Δημιουργία νέου τμήματος'), findsNothing);
  });

  testWidgets('το Enter δεν παρακάμπτει τον φρουρό', (tester) async {
    await openPicker(
      tester,
      available: [_dept(1, 'Πληροφορική')],
      blocked: const ['Δοκιμαστικό'],
    );

    await tester.enterText(find.byType(TextField), 'Δοκιμαστικό');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(closed, isFalse);
    expect(captured, isNull);
  });

  testWidgets('η σύγκριση αγνοεί πεζά και τόνους', (tester) async {
    await openPicker(
      tester,
      available: [_dept(1, 'Πληροφορική')],
      blocked: const ['Δοκιμαστικό'],
    );

    await tester.enterText(find.byType(TextField), 'δοκιμαστικο');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('διαγράφεται σε αυτή την πράξη'),
      findsOneWidget,
    );
  });

  testWidgets('θεμιτό νέο όνομα περνά κανονικά', (tester) async {
    await openPicker(
      tester,
      available: [_dept(1, 'Πληροφορική')],
      blocked: const ['Δοκιμαστικό'],
    );

    await tester.enterText(find.byType(TextField), 'Νέο Τμήμα');
    await tester.pumpAndSettle();

    expect(find.textContaining('διαγράφεται σε αυτή την πράξη'), findsNothing);
    expect(find.textContaining('Δημιουργία νέου τμήματος'), findsOneWidget);
  });

  testWidgets('χωρίς απαγορευμένα δεν εμποδίζεται τίποτα', (tester) async {
    await openPicker(tester, available: [_dept(1, 'Πληροφορική')]);

    await tester.enterText(find.byType(TextField), 'Δοκιμαστικό');
    await tester.pumpAndSettle();

    expect(find.textContaining('διαγράφεται σε αυτή την πράξη'), findsNothing);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Μεταφορά'),
    );
    expect(button.onPressed, isNotNull);
  });

  group('Όνομα που υπάρχει ήδη αλλά λείπει από τη λίστα', () {
    // Το τμήμα-πηγή εξαιρείται από τις επιλογές, αλλά **υπάρχει**: ο επιλυτής
    // προορισμού είναι get-or-create και θα κατέληγε σιωπηλά εκεί.
    Future<void> openForItem(WidgetTester tester) async {
      captured = null;
      closed = false;
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  captured = await showAssetTransferDialogForItem(
                    context: ctx,
                    isPhone: true,
                    value: '2100',
                    sourceDepartmentId: 1,
                    availableDepartments: [
                      _dept(1, 'Πληροφορική'),
                      _dept(2, 'Αιμοδοσία'),
                    ],
                  );
                  closed = true;
                },
                child: const Text('άνοιγμα'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('άνοιγμα'));
      await tester.pumpAndSettle();
    }

    testWidgets('δεν προτείνεται «δημιουργία νέου» για όνομα που υπάρχει', (
      tester,
    ) async {
      await openForItem(tester);

      await tester.enterText(find.byType(TextField), 'Πληροφορική');
      await tester.pumpAndSettle();

      expect(find.textContaining('Δημιουργία νέου τμήματος'), findsNothing);
    });

    testWidgets('η επιβεβαίωση λέει ότι το τμήμα υπάρχει, όχι ότι φτιάχνεται', (
      tester,
    ) async {
      await openForItem(tester);

      await tester.enterText(find.byType(TextField), 'πληροφορικη');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Μεταφορά'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Υπάρχει ήδη τμήμα με αυτό το όνομα: Πληροφορική.'),
        findsOneWidget,
      );
      expect(find.textContaining('Θα δημιουργηθεί νέο τμήμα'), findsNothing);
    });

    testWidgets('επιστρέφει το υπάρχον τμήμα, όχι αίτημα δημιουργίας', (
      tester,
    ) async {
      await openForItem(tester);

      await tester.enterText(find.byType(TextField), 'Πληροφορική');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Μεταφορά'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Μεταφορά εκεί'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(captured?.departmentId, 1);
      expect(captured?.newDepartmentName, isNull);
    });

    testWidgets('όνομα που όντως δεν υπάρχει κρατά τη δημιουργία', (
      tester,
    ) async {
      await openForItem(tester);

      await tester.enterText(find.byType(TextField), 'Ολοκαίνουριο');
      await tester.pumpAndSettle();

      expect(find.textContaining('Δημιουργία νέου τμήματος'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Μεταφορά'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Θα δημιουργηθεί νέο τμήμα: Ολοκαίνουριο'),
        findsOneWidget,
      );
    });
  });
}
