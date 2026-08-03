// Διάλογοι τοποθέτησης/σύγκρουσης βάσης Λάμπας: επιλογές, διαδρομές, μετακίνηση.
//
//   flutter test test/features/lamp/widgets/lamp_db_adoption_dialogs_test.dart

import 'package:call_logger/core/widgets/draggable_dialog_shell.dart';
import 'package:call_logger/features/lamp/widgets/lamp_db_adoption_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _picked = r'F:\call_logger\Data Base\old_equipment.db';
const String _appFolder = r'F:\call_logger\build\Debug\Data Base';
const String _destination =
    r'F:\call_logger\build\Debug\Data Base\old_equipment.db';
const String _keepBoth =
    r'F:\call_logger\build\Debug\Data Base\old_equipment_31-07-2026.db';

/// Κρατά την επιλογή που επιστρέφει ο διάλογος αφού κλείσει.
class _Captured<T> {
  T? value;
}

Future<_Captured<LampDbPlacementChoice>> _openPlacement(
  WidgetTester tester,
) async {
  final captured = _Captured<LampDbPlacementChoice>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured.value = await askLampDbPlacement(
                context,
                pickedPath: _picked,
                appFolderPath: _appFolder,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

Future<_Captured<LampDbConflictChoice>> _openConflict(
  WidgetTester tester, {
  required bool isConfiguredOutput,
}) async {
  final captured = _Captured<LampDbConflictChoice>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured.value = await askLampDbCopyConflict(
                context,
                sourcePath: _picked,
                destinationPath: _destination,
                keepBothPath: _keepBoth,
                destinationIsConfiguredOutput: isConfiguredOutput,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('askLampDbPlacement', () {
    testWidgets('δείχνει και τις δύο πλήρεις διαδρομές', (tester) async {
      await _openPlacement(tester);

      expect(find.text(_picked), findsOneWidget);
      expect(find.text(_appFolder), findsOneWidget);

      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();
    });

    testWidgets('«Αντιγραφή στον φάκελο» → copyToAppFolder', (tester) async {
      final captured = await _openPlacement(tester);
      await tester.tap(find.text('Αντιγραφή στον φάκελο'));
      await tester.pumpAndSettle();

      expect(captured.value, LampDbPlacementChoice.copyToAppFolder);
    });

    testWidgets('«Ανάγνωση από τη θέση του» → readInPlace', (tester) async {
      final captured = await _openPlacement(tester);
      await tester.tap(find.text('Ανάγνωση από τη θέση του'));
      await tester.pumpAndSettle();

      expect(captured.value, LampDbPlacementChoice.readInPlace);
    });

    testWidgets('«Ακύρωση» → cancel', (tester) async {
      final captured = await _openPlacement(tester);
      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();

      expect(captured.value, LampDbPlacementChoice.cancel);
    });

    testWidgets('είναι μετακινήσιμος', (tester) async {
      await _openPlacement(tester);

      expect(find.byType(DraggableDialogShell), findsOneWidget);

      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();
    });
  });

  group('askLampDbCopyConflict', () {
    testWidgets('δείχνει πηγή, προορισμό και το όνομα διατήρησης', (
      tester,
    ) async {
      await _openConflict(tester, isConfiguredOutput: false);

      expect(find.text(_picked), findsOneWidget);
      expect(find.text(_destination), findsOneWidget);
      expect(find.text(_keepBoth), findsOneWidget);

      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();
    });

    testWidgets('«Διατήρηση και των δύο» → keepBoth', (tester) async {
      final captured = await _openConflict(tester, isConfiguredOutput: false);
      await tester.tap(find.text('Διατήρηση και των δύο'));
      await tester.pumpAndSettle();

      expect(captured.value, LampDbConflictChoice.keepBoth);
    });

    testWidgets('«Αντικατάσταση» → replace', (tester) async {
      final captured = await _openConflict(tester, isConfiguredOutput: false);
      await tester.tap(find.text('Αντικατάσταση'));
      await tester.pumpAndSettle();

      expect(captured.value, LampDbConflictChoice.replace);
    });

    testWidgets('προειδοποιεί όταν ο προορισμός είναι η βάση εξόδου', (
      tester,
    ) async {
      await _openConflict(tester, isConfiguredOutput: true);

      expect(find.textContaining('δημιουργεί το Excel'), findsOneWidget);

      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();
    });

    testWidgets('χωρίς βάση εξόδου δεν εμφανίζεται προειδοποίηση', (
      tester,
    ) async {
      await _openConflict(tester, isConfiguredOutput: false);

      expect(find.textContaining('δημιουργεί το Excel'), findsNothing);

      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();
    });

    testWidgets('«Ακύρωση» → cancel', (tester) async {
      final captured = await _openConflict(tester, isConfiguredOutput: false);
      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();

      expect(captured.value, LampDbConflictChoice.cancel);
    });

    testWidgets('είναι μετακινήσιμος', (tester) async {
      await _openConflict(tester, isConfiguredOutput: false);

      expect(find.byType(DraggableDialogShell), findsOneWidget);

      await tester.tap(find.text('Ακύρωση'));
      await tester.pumpAndSettle();
    });
  });
}
