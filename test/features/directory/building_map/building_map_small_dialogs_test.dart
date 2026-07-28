// Widget tests: μικροί διάλογοι του χάρτη (επιβεβαιώσεις, επιλογείς άλματος,
// διαγραφή φύλλου κατόψης).
//
//   flutter test test/features/directory/building_map/building_map_small_dialogs_test.dart

import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/building_map/widgets/building_map_confirm_dialogs.dart';
import 'package:call_logger/features/directory/building_map/widgets/building_map_floor_delete_dialog.dart';
import 'package:call_logger/features/directory/building_map/widgets/building_map_jump_pick_dialogs.dart';
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

  group('Διάλογοι επιβεβαίωσης', () {
    testWidgets('επικάλυψη: «Συνέχεια» → true, «Άκυρο» → false', (
      tester,
    ) async {
      bool? result;
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapOverlapConfirmDialog(context);
      });
      await tester.tap(find.text('Συνέχεια'));
      await tester.pumpAndSettle();
      expect(result, isTrue);

      await tester.tap(find.text(_kOpenButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Άκυρο'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('αφαίρεση τμήματος: δείχνει το όνομα και «Αφαίρεση» → true', (
      tester,
    ) async {
      bool? result;
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapRemoveDepartmentConfirmDialog(
          context,
          departmentName: 'Βιοχημικό',
        );
      });
      expect(find.textContaining('«Βιοχημικό»'), findsOneWidget);
      await tester.tap(find.text('Αφαίρεση'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('εντοπισμός μέσω υπαλλήλου: δείχνει το όνομα και '
        '«Άκυρο» → false', (tester) async {
      bool? result;
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapJumpToUserConfirmDialog(
          context,
          userDisplayName: 'Βαρβάρα Ψαρρά',
        );
      });
      expect(find.textContaining('Βαρβάρα Ψαρρά'), findsOneWidget);
      await tester.tap(find.text('Άκυρο'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });

  group('Επιλογείς άλματος', () {
    testWidgets('επιλογή υπαλλήλου: fallback «Χωρίς όνομα» και επιστροφή '
        'του επιλεγμένου', (tester) async {
      final withName = UserModel(id: 1, firstName: 'Βαρβάρα', lastName: 'Ψαρρά');
      final nameless = UserModel(id: 2);
      UserModel? result;
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapUserPickDialog(
          context,
          users: [withName, nameless],
        );
      });
      expect(find.text('Χωρίς όνομα'), findsOneWidget);
      await tester.tap(find.textContaining('Ψαρρά'));
      await tester.pumpAndSettle();
      expect(result, same(withName));
    });

    testWidgets('επιλογή τμήματος: επιστρέφει το αναγνωριστικό της ετικέτας '
        'που πατήθηκε', (tester) async {
      int? result;
      await _pumpHost(tester, (context) async {
        result = await showBuildingMapDepartmentPickDialog(
          context,
          options: const [
            (id: 3, label: 'Γραμματεία ΤΕΠ'),
            (id: 9, label: 'Τμήμα #9'),
          ],
        );
      });
      await tester.tap(find.text('Γραμματεία ΤΕΠ'));
      await tester.pumpAndSettle();
      expect(result, 3);
    });
  });

  group('Διάλογος «Διαγραφή ορόφου»', () {
    testWidgets('με εικόνα στον δίσκο: ο διακόπτης ενεργός, η ενεργοποίησή '
        'του γυρίζει deleteImageFile=true', (tester) async {
      BuildingMapFloorDeleteChoice? choice;
      await _pumpHost(tester, (context) async {
        choice = await showBuildingMapFloorDeleteDialog(
          context,
          displayImagePath: r'C:\maps\2ος.png',
          imageFileExists: true,
          showMissingImageNote: false,
        );
      });
      expect(find.text(r'C:\maps\2ος.png'), findsOneWidget);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        find.text('Η εικόνα του χάρτη θα διαγραφεί οριστικά από το δίσκο.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Διαγραφή'));
      await tester.pumpAndSettle();
      expect(choice, isNotNull);
      expect(choice!.deleteImageFile, isTrue);
    });

    testWidgets('χωρίς εικόνα: ο διακόπτης ανενεργός και η «Διαγραφή» '
        'επιστρέφει deleteImageFile=false', (tester) async {
      BuildingMapFloorDeleteChoice? choice;
      await _pumpHost(tester, (context) async {
        choice = await showBuildingMapFloorDeleteDialog(
          context,
          displayImagePath: null,
          imageFileExists: false,
          showMissingImageNote: true,
        );
      });
      expect(
        find.text('Το αρχείο εικόνας δεν βρέθηκε στο δίσκο.'),
        findsOneWidget,
      );
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.onChanged, isNull);

      await tester.tap(find.text('Διαγραφή'));
      await tester.pumpAndSettle();
      expect(choice, isNotNull);
      expect(choice!.deleteImageFile, isFalse);
    });

    testWidgets('το «Άκυρο» επιστρέφει null', (tester) async {
      BuildingMapFloorDeleteChoice? choice = const BuildingMapFloorDeleteChoice(
        deleteImageFile: true,
      );
      await _pumpHost(tester, (context) async {
        choice = await showBuildingMapFloorDeleteDialog(
          context,
          displayImagePath: null,
          imageFileExists: false,
          showMissingImageNote: false,
        );
      });
      await tester.tap(find.text('Άκυρο'));
      await tester.pumpAndSettle();
      expect(choice, isNull);
    });
  });
}
