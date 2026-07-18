// Widget test: snackbar διαγραφής DepartmentsTab — κλείσιμο με Χ μετά dispose του tab.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/departments_tab_snackbar_test.dart

import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/features/directory/building_map/providers/building_map_providers.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/departments_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_setup.dart';

class _FakeDepartmentDirectoryNotifier extends DepartmentDirectoryNotifier {
  _FakeDepartmentDirectoryNotifier(this._initialState);

  final DepartmentDirectoryState _initialState;

  @override
  DepartmentDirectoryState build() => _initialState;

  @override
  Future<void> loadDepartments() async {}

  @override
  Future<void> deleteSelected() async {
    if (state.selectedIds.isEmpty) return;
    final toDelete = state.allDepartments
        .where(
          (d) =>
              d.id != null &&
              !d.isDeleted &&
              state.selectedIds.contains(d.id),
        )
        .toList();
    if (toDelete.isEmpty) return;
    final remaining = state.allDepartments
        .where((d) => d.id == null || !state.selectedIds.contains(d.id))
        .toList();
    state = DepartmentDirectoryState(
      allDepartments: remaining,
      filteredDepartments: remaining,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: {},
      lastDeleted: toDelete,
      lastBulkUpdatedDepartments: state.lastBulkUpdatedDepartments,
      focusedRowIndex: null,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
  }

  @override
  Future<void> undoLastDelete() async {
    state = DepartmentDirectoryState(
      allDepartments: state.allDepartments,
      filteredDepartments: state.filteredDepartments,
      searchQuery: state.searchQuery,
      sortColumn: state.sortColumn,
      sortAscending: state.sortAscending,
      selectedIds: state.selectedIds,
      lastDeleted: null,
      lastBulkUpdatedDepartments: state.lastBulkUpdatedDepartments,
      focusedRowIndex: state.focusedRowIndex,
      columnOrder: state.columnOrder,
      visibleColumnKeys: state.visibleColumnKeys,
    );
  }
}

class _DepartmentsTabHost extends StatefulWidget {
  const _DepartmentsTabHost();

  @override
  State<_DepartmentsTabHost> createState() => _DepartmentsTabHostState();
}

class _DepartmentsTabHostState extends State<_DepartmentsTabHost> {
  bool _showTab = true;

  void removeTab() => setState(() => _showTab = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _showTab ? const DepartmentsTab() : const SizedBox.shrink(),
    );
  }
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  testWidgets(
    'DepartmentsTab: πάτημα Χ στο snackbar διαγραφής μετά dispose του tab δεν ρίχνει εξαίρεση',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const deptId = 9002;
      final department = DepartmentModel(
        id: deptId,
        name: 'Snack Τμήμα',
      );
      final initial = DepartmentDirectoryState(
        allDepartments: [department],
        filteredDepartments: [department],
        selectedIds: {deptId},
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...callLoggerTestProviderOverrides(),
            departmentDirectoryProvider.overrideWith(
              () => _FakeDepartmentDirectoryNotifier(initial),
            ),
            catalogDepartmentsContinuousScrollProvider.overrideWith(
              (ref) async => true,
            ),
            buildingMapFloorsCatalogProvider.overrideWith(
              (ref) async => const <BuildingMapFloor>[],
            ),
          ],
          child: const MaterialApp(home: _DepartmentsTabHost()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Διαγραφή'), findsOneWidget);
      await tester.tap(find.text('Διαγραφή'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Διαγραφή'),
        ),
      );
      for (var i = 0;
          i < 60 && find.byType(SnackBar).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Σημειώθηκαν ως διαγραμμένα'), findsOneWidget);

      final hostState =
          tester.state(find.byType(_DepartmentsTabHost)) as _DepartmentsTabHostState;
      hostState.removeTab();
      await tester.pump();

      expect(find.byType(DepartmentsTab), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);

      final closeIcon = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byIcon(Icons.close),
      );
      expect(closeIcon, findsOneWidget);
      final closeButtonFinder = find.ancestor(
        of: closeIcon,
        matching: find.byType(IconButton),
      );
      expect(closeButtonFinder, findsOneWidget);
      final closeButton = tester.widget<IconButton>(closeButtonFinder);
      expect(closeButton.onPressed, isNotNull);
      closeButton.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);

      await flushCallLoggerSqfliteLockTimers(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
