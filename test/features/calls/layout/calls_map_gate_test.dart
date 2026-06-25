import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/layout/calls_field_confirmations.dart';
import 'package:call_logger/features/calls/layout/calls_field_groups.dart';
import 'package:call_logger/features/calls/layout/calls_layout_engine.dart';
import 'package:call_logger/features/calls/layout/calls_layout_plan.dart';
import 'package:call_logger/features/calls/layout/calls_map_gate.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter_test/flutter_test.dart';

DepartmentModel _mappedDept({required int id}) {
  return DepartmentModel(
    id: id,
    name: 'Mapped $id',
    mapX: 0.1,
    mapY: 0.1,
    mapWidth: 0.2,
    mapHeight: 0.2,
    mapFloor: '1',
  );
}

void main() {
  group('CallsMapGate', () {
    test('τηλέφωνο χωρίς χαρτογραφημένο τμήμα → ΧΑ ανενεργό', () {
      final lookup = LookupService.forTest();
      lookup.injectInMemoryCatalogForTests(
        users: const [],
        equipment: const [],
        departmentRows: [
          DepartmentModel(id: 1, name: 'No map'),
        ],
      );

      expect(
        CallsMapGate.phoneResolvesToMappedDepartment(lookup, '2862'),
        isFalse,
      );
      expect(
        CallsMapGate.isMapActive(
          SmartEntitySelectorState(selectedPhone: '2862'),
          lookup,
        ),
        isFalse,
      );
      expect(
        CallsMapGate.isMapActive(
          SmartEntitySelectorState(selectedPhone: '2862'),
          lookup,
          const CallsFieldConfirmations(phone: true),
        ),
        isFalse,
      );
    });

    test('μη επιβεβαιωμένο τηλέφωνο → ΧΑ ανενεργό ακόμα κι αν ταιριάζει', () {
      final lookup = LookupService.forTest();
      lookup.injectInMemoryCatalogForTests(
        users: const [],
        equipment: const [],
        departmentRows: [
          _mappedDept(id: 5).copyWith(directPhones: ['2893']),
        ],
      );

      expect(
        CallsMapGate.isMapActive(
          SmartEntitySelectorState(selectedPhone: '2893'),
          lookup,
        ),
        isFalse,
      );
    });

    test('prefix τηλεφώνου δεν ενεργοποιεί ΧΑ — μόνο ακριβές ταίριασμα', () {
      final lookup = LookupService.forTest();
      lookup.injectInMemoryCatalogForTests(
        users: const [],
        equipment: const [],
        departmentRows: [
          _mappedDept(id: 5).copyWith(directPhones: ['2893']),
        ],
      );

      expect(
        CallsMapGate.phoneResolvesToMappedDepartment(lookup, '289'),
        isFalse,
      );
      expect(
        CallsMapGate.isMapActive(
          SmartEntitySelectorState(selectedPhone: '289'),
          lookup,
          const CallsFieldConfirmations(phone: true),
        ),
        isFalse,
      );
      expect(
        CallsMapGate.isMapActive(
          SmartEntitySelectorState(selectedPhone: '2893'),
          lookup,
          const CallsFieldConfirmations(phone: true),
        ),
        isTrue,
      );
    });

    test('τηλέφωνο με χαρτογραφημένο τμήμα (direct) → ΧΑ ενεργό', () {
      final lookup = LookupService.forTest();
      lookup.injectInMemoryCatalogForTests(
        users: const [],
        equipment: const [],
        departmentRows: [
          _mappedDept(id: 5).copyWith(directPhones: ['2001']),
        ],
      );

      expect(
        CallsMapGate.phoneResolvesToMappedDepartment(lookup, '2001'),
        isTrue,
      );
    });
  });

  group('Πρότυπο Α — χάρτης', () {
    test('μόνο τηλέφωνο χωρίς θέση στο χάρτη: 2 γραμμές περιεχομένου', () {
      final groups = CallsFieldGroupsResolver.resolve(
        SmartEntitySelectorState(selectedPhone: '2862'),
        const CallsFieldConfirmations(phone: true),
      );
      final vis = CallsLayoutVisibility(
        showUserCard: false,
        showMapCard: groups.isMapActive,
        showEmployeeRecentCard: false,
        showEquipmentRecentPanel: false,
        showGlobalRecentCard: false,
        showRemoteTools: false,
        hasCallerHistoryData: false,
        hasEquipmentHistoryData: false,
      );
      final plan = CallsLayoutEngine.build(groups, vis);
      expect(plan.rows.length, 2);
      expect(
        plan.allSlots,
        isNot(contains(CallsLayoutSlot.map)),
      );
    });
  });
}