// Widget tests: διάλογοι «Νέο φύλλο κατόψης» και «Επεξεργασία κατόψης».
//
//   flutter test test/features/directory/building_map/building_map_floor_sheet_dialogs_test.dart

import 'dart:io';

import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/features/directory/building_map/widgets/building_map_floor_sheet_add_dialog.dart';
import 'package:call_logger/features/directory/building_map/widgets/building_map_floor_sheet_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../test_setup.dart';

const _kOpenButton = 'OPEN_DIALOG';

BuildingMapFloor _floor({String label = '2ος - Καρδιολογική'}) {
  return BuildingMapFloor(
    id: 5,
    sortOrder: 1,
    label: label,
    floorGroup: 'L2',
    imagePath: '',
    rotationDegrees: 0,
  );
}

Future<void> _pumpHost(
  WidgetTester tester,
  Future<void> Function(BuildContext context) onOpen,
) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...callLoggerTestProviderOverrides(),
        enableSpellCheckProvider.overrideWith((ref) async => false),
        spellCheckServiceProvider.overrideWith((ref) async {
          final svc = LexiconSpellCheckService();
          await svc.init(lexiconVariants: {});
          return svc;
        }),
      ],
      child: MaterialApp(
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
    ),
  );

  await tester.tap(find.text(_kOpenButton));
  await pumpUntilSettled(tester);
}

FilledButton _filledButton(WidgetTester tester, String label) {
  return tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerCallLoggerIsolatedDatabaseHooks();

  group('Διάλογος «Νέο φύλλο κατόψης»', () {
    testWidgets('η «Προσθήκη» ενεργοποιείται μόνο με μη κενή ετικέτα και '
        'επιστρέφει trimmed αποτέλεσμα', (tester) async {
      BuildingMapFloorSheetAddResult? result;
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapFloorSheetAddDialog(context);
      });

      expect(_filledButton(tester, 'Προσθήκη').onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ετικέτα'),
        '  1ος — Γραφεία  ',
      );
      await tester.pump();
      expect(_filledButton(tester, 'Προσθήκη').onPressed, isNotNull);

      await tester.tap(find.text('Προσθήκη'));
      await pumpUntilSettled(tester);

      expect(result, isNotNull);
      expect(result!.label, '1ος — Γραφεία');
      expect(result!.floorGroup, isNull);
    });

    testWidgets('το «Άκυρο» επιστρέφει null', (tester) async {
      BuildingMapFloorSheetAddResult? result =
          const BuildingMapFloorSheetAddResult(label: 'φρουρός');
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapFloorSheetAddDialog(context);
      });

      await tester.tap(find.text('Άκυρο'));
      await pumpUntilSettled(tester);

      expect(result, isNull);
    });
  });

  group('Διάλογος «Επεξεργασία κατόψης»', () {
    testWidgets('χωρίς αλλαγές η «Αποθήκευση» είναι ανενεργή· αλλαγή ονόματος '
        'την ενεργοποιεί και επιστρέφεται το νέο όνομα', (tester) async {
      BuildingMapFloorSheetEditResult? result;
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapFloorSheetEditDialog(
          context,
          floor: _floor(),
          previewDepartments: const [],
          initialPreviewImageAvailable: false,
          pickImagePath: () async => null,
        );
      });

      expect(_filledButton(tester, 'Αποθήκευση').onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, '2ος - Καρδιολογική'),
        '2ος - Καρδιολογική-Παθολογική',
      );
      await tester.pump();
      expect(_filledButton(tester, 'Αποθήκευση').onPressed, isNotNull);

      await tester.tap(find.text('Αποθήκευση'));
      await pumpUntilSettled(tester);

      expect(result, isNotNull);
      expect(result!.label, '2ος - Καρδιολογική-Παθολογική');
      expect(result!.floorGroupRaw, 'L2');
      expect(result!.pickedSrcPath, isNull);
    });

    testWidgets('η «Αλλαγή κατόψης» καλεί τον ενιέμενο επιλογέα και το '
        'αποτέλεσμα μεταφέρει τη νέα εικόνα', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('map_dialog_test_');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final imageFile = File(p.join(tempDir.path, 'κατόψη.png'))
        ..writeAsStringSync('x');

      var pickerCalls = 0;
      BuildingMapFloorSheetEditResult? result;
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapFloorSheetEditDialog(
          context,
          floor: _floor(),
          previewDepartments: const [],
          initialPreviewImageAvailable: false,
          pickImagePath: () async {
            pickerCalls++;
            return imageFile.path;
          },
        );
      });

      await tester.tap(find.text('Αλλαγή κατόψης'));
      await pumpUntilSettled(tester);

      expect(pickerCalls, 1);
      expect(find.text('Επιλέχθηκε νέα κατόψη'), findsOneWidget);
      expect(_filledButton(tester, 'Αποθήκευση').onPressed, isNotNull);

      await tester.tap(find.text('Αποθήκευση'));
      await pumpUntilSettled(tester);

      expect(result, isNotNull);
      expect(result!.pickedSrcPath, imageFile.path);
      expect(result!.label, '2ος - Καρδιολογική');
    });

    testWidgets('το «Άκυρο» επιστρέφει null χωρίς να καλέσει τον επιλογέα', (
      tester,
    ) async {
      var pickerCalls = 0;
      BuildingMapFloorSheetEditResult? result =
          const BuildingMapFloorSheetEditResult(
            label: 'φρουρός',
            floorGroupRaw: '',
          );
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapFloorSheetEditDialog(
          context,
          floor: _floor(),
          previewDepartments: const [],
          initialPreviewImageAvailable: false,
          pickImagePath: () async {
            pickerCalls++;
            return null;
          },
        );
      });

      await tester.tap(find.text('Άκυρο'));
      await pumpUntilSettled(tester);

      expect(result, isNull);
      expect(pickerCalls, 0);
    });
  });
}
