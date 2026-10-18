// Unit tests: τι απογίνεται η σχεδίαση όταν αλλάζει ο όροφος από την καρτέλα.
//
//   flutter test test/features/directory/department_floor_change_outcome_test.dart

import 'package:call_logger/features/directory/services/building_map_floor_load_state.dart';
import 'package:call_logger/features/directory/services/department_floor_change_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

DepartmentFloorChangeAction _resolve({
  bool isEdit = true,
  bool leavesTheBuildingMap = false,
  int? selectedFloorId,
  int? snapshotFloorId,
  int? initialFloorId,
  bool hasDrawnPlacement = false,
  int? placementFloorId,
  BuildingMapFloorLoadState floorLoadState = BuildingMapFloorLoadState.loaded,
}) {
  return resolveDepartmentFloorChange(
    isEdit: isEdit,
    leavesTheBuildingMap: leavesTheBuildingMap,
    selectedFloorId: selectedFloorId,
    snapshotFloorId: snapshotFloorId,
    initialFloorId: initialFloorId,
    hasDrawnPlacement: hasDrawnPlacement,
    placementFloorId: placementFloorId,
    floorLoadState: floorLoadState,
  );
}

void main() {
  group('αλλαγή ορόφου με σχεδιασμένο τμήμα', () {
    test('σχεδιασμένο στο Ισόγειο, ο χρήστης βάζει 1ο → ρωτά', () {
      expect(
        _resolve(
          selectedFloorId: 2,
          snapshotFloorId: 1,
          initialFloorId: 1,
          hasDrawnPlacement: true,
          placementFloorId: 1,
        ),
        DepartmentFloorChangeAction.askMoveOrClear,
      );
    });

    test('ίδιος όροφος: καμία ερώτηση', () {
      expect(
        _resolve(
          selectedFloorId: 1,
          snapshotFloorId: 1,
          initialFloorId: 1,
          hasDrawnPlacement: true,
          placementFloorId: 1,
        ),
        DepartmentFloorChangeAction.keepPlacement,
      );
    });

    test('τμήμα χωρίς σχέδιο: αλλάζει όροφο σιωπηλά', () {
      expect(
        _resolve(
          selectedFloorId: 2,
          snapshotFloorId: 1,
          initialFloorId: 1,
          hasDrawnPlacement: false,
          placementFloorId: 1,
        ),
        DepartmentFloorChangeAction.keepPlacement,
      );
    });

    test('άγνωστες κατόψεις: ούτε ερώτηση ούτε σβήσιμο', () {
      expect(
        _resolve(
          selectedFloorId: 2,
          snapshotFloorId: 1,
          initialFloorId: 1,
          hasDrawnPlacement: true,
          placementFloorId: 1,
          floorLoadState: BuildingMapFloorLoadState.failed,
        ),
        DepartmentFloorChangeAction.keepPlacement,
      );
    });
  });

  // Η δεύτερη γραμμή άμυνας: ακόμη κι αν κάτι φτάσει στην αποθήκευση με
  // άγνωστες κατόψεις, η χαρτογράφηση δεν σβήνεται.
  group('σβήσιμο θέσης στον χάρτη', () {
    test('άγνωστες κατόψεις: ΔΕΝ σβήνεται η χαρτογράφηση', () {
      expect(
        _resolve(
          selectedFloorId: null,
          snapshotFloorId: 12,
          initialFloorId: 12,
          floorLoadState: BuildingMapFloorLoadState.failed,
        ),
        DepartmentFloorChangeAction.keepPlacement,
      );
    });

    test('όσο φορτώνει: ΔΕΝ σβήνεται η χαρτογράφηση', () {
      expect(
        _resolve(
          selectedFloorId: null,
          snapshotFloorId: 12,
          initialFloorId: 12,
          floorLoadState: BuildingMapFloorLoadState.loading,
        ),
        DepartmentFloorChangeAction.keepPlacement,
      );
    });

    test('διαβασμένες κατόψεις: το ηθελημένο σβήσιμο ισχύει κανονικά', () {
      expect(
        _resolve(
          selectedFloorId: null,
          snapshotFloorId: 12,
          initialFloorId: 12,
        ),
        DepartmentFloorChangeAction.clearPlacement,
      );
    });

    // Η «Καρδιολογική», σχεδιασμένη στον 2ο, παίρνει όροφο «— χωρίς —»: η
    // σχεδίαση χάνεται οριστικά, άρα ο χρήστης ρωτιέται πριν την αποθήκευση —
    // όπως ήδη στην αλλαγή σε άλλον όροφο και στην αλλαγή Είδους.
    test('σχεδιασμένο τμήμα χάνει τον όροφο: ζητά επιβεβαίωση', () {
      expect(
        _resolve(
          selectedFloorId: null,
          snapshotFloorId: 2,
          initialFloorId: 2,
          hasDrawnPlacement: true,
          placementFloorId: 2,
        ),
        DepartmentFloorChangeAction.confirmClearPlacement,
      );
    });

    test('νέο τμήμα δεν έχει τίποτα να σβήσει', () {
      expect(
        _resolve(isEdit: false, selectedFloorId: null),
        DepartmentFloorChangeAction.keepPlacement,
      );
    });

    test(
      'το Είδος βγάζει την καρτέλα από την κάτοψη: σβήνει χωρίς ερώτηση',
      () {
        expect(
          _resolve(
            leavesTheBuildingMap: true,
            selectedFloorId: 2,
            snapshotFloorId: 1,
            initialFloorId: 1,
            hasDrawnPlacement: true,
            placementFloorId: 1,
          ),
          DepartmentFloorChangeAction.clearPlacement,
        );
      },
    );
  });
}
