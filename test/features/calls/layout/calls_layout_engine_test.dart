import 'package:flutter_test/flutter_test.dart';

import 'package:call_logger/features/calls/layout/calls_field_groups.dart';
import 'package:call_logger/features/calls/layout/calls_layout_engine.dart';
import 'package:call_logger/features/calls/layout/calls_layout_plan.dart';
import 'package:call_logger/features/calls/layout/calls_layout_template.dart';

CallsFieldGroups _groups({
  bool phone = false,
  EquipmentGroupTier equipment = EquipmentGroupTier.none,
  bool caller = false,
  bool map = false,
}) {
  final template = CallsLayoutTemplateSelector.select(
    isPhoneGroupActive: phone,
    isCallerGroupActive: caller,
    equipmentTier: equipment,
    isMapActive: map,
  );
  return CallsFieldGroups(
    isPhoneGroupActive: phone,
    equipmentTier: equipment,
    isCallerGroupActive: caller,
    isMapActive: map,
    template: template,
  );
}

CallsLayoutVisibility _visFor(CallsFieldGroups groups, {bool globalRecent = true}) {
  return CallsLayoutVisibility(
    showUserCard: groups.isCallerGroupActive,
    showMapCard: groups.isMapActive,
    showEmployeeRecentCard: groups.isCallerGroupActive,
    showEquipmentRecentPanel:
        groups.equipmentTier == EquipmentGroupTier.matchedRecord,
    showGlobalRecentCard: globalRecent,
    showRemoteTools: groups.isEquipmentGroupActive,
    hasCallerHistoryData: groups.isCallerGroupActive,
    hasEquipmentHistoryData:
        groups.equipmentTier == EquipmentGroupTier.matchedRecord,
  );
}

void main() {
  group('CallsLayoutEngine — 15 combinations (table 8.8)', () {
    test('#1 phone only — template A: σημειώσεις, ενέργειες, χωρίς χάρτη', () {
      final g = _groups(phone: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.a);
      expect(plan.rows.length, 3);
      expect(plan.rows[0].columns.single.slots, [CallsLayoutSlot.notes]);
      // Κατηγορία+χρονόμετρο+Καταγραφή = ενιαίο slot (μία γραμμή, κανόνας 3).
      expect(
        plan.rows[1].columns.map((c) => c.slots.first).toList(),
        [CallsLayoutSlot.categoryPending],
      );
      expect(plan.allSlots, isNot(contains(CallsLayoutSlot.map)));
      expect(plan.allSlots, contains(CallsLayoutSlot.globalRecent));
      expect(plan.allSlots, isNot(contains(CallsLayoutSlot.callerCard)));
    });

    test('#1+ΧΑ phone only + map — template A: χάρτης/ΤΚ στη 3η γραμμή', () {
      final g = _groups(phone: true, map: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.rows.length, 3);
      expect(
        plan.rows[2].columns.map((c) => c.single).whereType<CallsLayoutSlot>(),
        containsAll([CallsLayoutSlot.map, CallsLayoutSlot.globalRecent]),
      );
    });

    test('#2 phone + caller — template A with row3 caller stack', () {
      final g = _groups(phone: true, caller: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.a);
      expect(plan.allSlots, contains(CallsLayoutSlot.callerCard));
    });

    test('#3 phone + equipment — template A with equipment history col', () {
      final g = _groups(phone: true, equipment: EquipmentGroupTier.matchedRecord);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.allSlots, contains(CallsLayoutSlot.equipmentHistory));
    });

    test('#4 phone + map — template A row3 map', () {
      final g = _groups(phone: true, map: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.allSlots, contains(CallsLayoutSlot.map));
    });

    test('#5 phone + caller + equipment — template A', () {
      final g = _groups(
        phone: true,
        caller: true,
        equipment: EquipmentGroupTier.matchedRecord,
      );
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.a);
      expect(plan.rows.length, greaterThanOrEqualTo(2));
    });

    test('#6 phone + caller + map — template A', () {
      final g = _groups(phone: true, caller: true, map: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.allSlots, containsAll([CallsLayoutSlot.callerCard, CallsLayoutSlot.map]));
    });

    test('#7 phone + equipment + map — template A', () {
      final g = _groups(
        phone: true,
        equipment: EquipmentGroupTier.matchedRecord,
        map: true,
      );
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.allSlots, contains(CallsLayoutSlot.map));
    });

    test('#8 full template A — all major slots, σημειώσεις στη γραμμή 2', () {
      final g = _groups(
        phone: true,
        caller: true,
        equipment: EquipmentGroupTier.matchedRecord,
        map: true,
      );
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.a);
      expect(
        plan.rows[0].columns.first.slots,
        containsAll([
          CallsLayoutSlot.notes,
          CallsLayoutSlot.categoryPending,
        ]),
      );
      expect(plan.allSlots, containsAll([
        CallsLayoutSlot.notes,
        CallsLayoutSlot.remoteTools,
        CallsLayoutSlot.equipmentHistory,
        CallsLayoutSlot.callerCard,
        CallsLayoutSlot.map,
        CallsLayoutSlot.globalRecent,
      ]));
    });

    test('#9 caller only no map — template C stack', () {
      final g = _groups(caller: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.c);
      expect(plan.allSlots, contains(CallsLayoutSlot.callerCard));
      expect(plan.allSlots, isNot(contains(CallsLayoutSlot.map)));
    });

    test('#10 equipment only no map — template D', () {
      final g = _groups(equipment: EquipmentGroupTier.matchedRecord);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.d);
      expect(plan.allSlots, contains(CallsLayoutSlot.remoteTools));
      expect(plan.allSlots, isNot(contains(CallsLayoutSlot.map)));
    });

    test('#11 map only — template B map row', () {
      final g = _groups(map: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.b);
      expect(plan.allSlots, contains(CallsLayoutSlot.map));
    });

    test('#12 caller + equipment no map — template B split caller rows', () {
      final g = _groups(
        caller: true,
        equipment: EquipmentGroupTier.matchedRecord,
      );
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.b);
      expect(plan.allSlots, contains(CallsLayoutSlot.remoteTools));
      expect(plan.allSlots, contains(CallsLayoutSlot.callerCard));
      expect(plan.allSlots, contains(CallsLayoutSlot.callerHistory));
    });

    test('#13 caller + map — template C with map column', () {
      final g = _groups(caller: true, map: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.c);
      expect(plan.allSlots, containsAll([CallsLayoutSlot.callerCard, CallsLayoutSlot.map]));
    });

    test('#14 equipment + map — template D with map', () {
      final g = _groups(
        equipment: EquipmentGroupTier.matchedRecord,
        map: true,
      );
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.d);
      expect(plan.allSlots, contains(CallsLayoutSlot.map));
    });

    test('#15 full template B without phone', () {
      final g = _groups(
        caller: true,
        equipment: EquipmentGroupTier.matchedRecord,
        map: true,
      );
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.b);
      expect(plan.rows.length, greaterThanOrEqualTo(3));
    });
  });
}
