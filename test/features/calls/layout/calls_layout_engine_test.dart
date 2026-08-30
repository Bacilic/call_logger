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

CallsLayoutVisibility _visFor(
  CallsFieldGroups groups, {
  bool globalRecent = true,
}) {
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
      expect(plan.rows[1].columns.map((c) => c.slots.first).toList(), [
        CallsLayoutSlot.categoryPending,
      ]);
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
      final g = _groups(
        phone: true,
        equipment: EquipmentGroupTier.matchedRecord,
      );
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
      expect(
        plan.allSlots,
        containsAll([CallsLayoutSlot.callerCard, CallsLayoutSlot.map]),
      );
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
        containsAll([CallsLayoutSlot.notes, CallsLayoutSlot.categoryPending]),
      );
      expect(
        plan.allSlots,
        containsAll([
          CallsLayoutSlot.notes,
          CallsLayoutSlot.remoteTools,
          CallsLayoutSlot.equipmentHistory,
          CallsLayoutSlot.callerCard,
          CallsLayoutSlot.map,
          CallsLayoutSlot.globalRecent,
        ]),
      );
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

    test(
      '#12 caller + equipment no map — template B: remote στην 1η γραμμή',
      () {
        final g = _groups(
          caller: true,
          equipment: EquipmentGroupTier.matchedRecord,
        );
        final plan = CallsLayoutEngine.build(g, _visFor(g));
        expect(plan.template, CallsLayoutTemplate.b);
        expect(plan.allSlots, contains(CallsLayoutSlot.remoteTools));
        expect(plan.allSlots, contains(CallsLayoutSlot.callerCard));
        expect(plan.allSlots, contains(CallsLayoutSlot.callerHistory));
        final firstRowSlots = plan.rows.first.columns
            .map((c) => c.single)
            .whereType<CallsLayoutSlot>();
        expect(firstRowSlots, contains(CallsLayoutSlot.remoteTools));
        expect(firstRowSlots, contains(CallsLayoutSlot.callerCard));
        expect(
          plan.rows.any(
            (r) =>
                r.columns.length == 1 &&
                r.columns.single.single == CallsLayoutSlot.remoteTools,
          ),
          isFalse,
          reason: 'το remote δεν πρέπει να είναι μόνο του σε ξεχωριστή γραμμή',
        );
      },
    );

    test('#13 caller + map — template C with map column', () {
      final g = _groups(caller: true, map: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.c);
      expect(
        plan.allSlots,
        containsAll([CallsLayoutSlot.callerCard, CallsLayoutSlot.map]),
      );
    });

    test('#14 equipment + map — template D: remote + χάρτης ίδια γραμμή', () {
      final g = _groups(equipment: EquipmentGroupTier.matchedRecord, map: true);
      final plan = CallsLayoutEngine.build(g, _visFor(g));
      expect(plan.template, CallsLayoutTemplate.d);
      expect(plan.allSlots, contains(CallsLayoutSlot.map));
      final firstRowSlots = plan.rows.first.columns
          .map((c) => c.single)
          .whereType<CallsLayoutSlot>();
      expect(
        firstRowSlots,
        containsAll([CallsLayoutSlot.remoteTools, CallsLayoutSlot.map]),
      );
    });

    test(
      '#15 full template B without phone — remote στην 1η γραμμή με χάρτη',
      () {
        final g = _groups(
          caller: true,
          equipment: EquipmentGroupTier.matchedRecord,
          map: true,
        );
        final plan = CallsLayoutEngine.build(g, _visFor(g));
        expect(plan.template, CallsLayoutTemplate.b);
        expect(plan.rows.length, greaterThanOrEqualTo(2));
        final firstRowSlots = plan.rows.first.columns
            .map((c) => c.single)
            .whereType<CallsLayoutSlot>();
        expect(
          firstRowSlots.toList(),
          containsAll([
            CallsLayoutSlot.remoteTools,
            CallsLayoutSlot.map,
            CallsLayoutSlot.callerCard,
          ]),
        );
        expect(
          firstRowSlots.first,
          CallsLayoutSlot.remoteTools,
          reason: 'σειρά: εργαλεία → χάρτης → καλούντας',
        );
        expect(
          firstRowSlots,
          isNot(contains(CallsLayoutSlot.equipmentHistory)),
          reason:
              'το ιστορικό εξοπλισμού δεν μπαίνει στην 1η γραμμή (αποφυγή 4 στηλών)',
        );
        expect(
          plan.rows.any(
            (r) =>
                r.columns.length == 1 &&
                r.columns.single.single == CallsLayoutSlot.remoteTools,
          ),
          isFalse,
          reason: 'το remote δεν πρέπει να είναι μόνο του σε ξεχωριστή γραμμή',
        );
      },
    );
  });

  group('Εφεδρική κάρτα «Ενέργειες υπολογιστή»', () {
    CallsLayoutVisibility visibility(
      CallsFieldGroups groups, {
      required bool hasCalls,
      bool historyCardEnabled = true,
    }) {
      return CallsLayoutVisibility(
        showUserCard: groups.isCallerGroupActive,
        showMapCard: groups.isMapActive,
        showEmployeeRecentCard: groups.isCallerGroupActive,
        showEquipmentRecentPanel:
            historyCardEnabled &&
            groups.equipmentTier == EquipmentGroupTier.matchedRecord &&
            hasCalls,
        showGlobalRecentCard: false,
        showRemoteTools: groups.isEquipmentGroupActive,
        hasCallerHistoryData: groups.isCallerGroupActive,
        hasEquipmentHistoryData: hasCalls,
      );
    }

    test('εξοπλισμός με κλήσεις → μόνο το ιστορικό', () {
      final g = _groups(equipment: EquipmentGroupTier.matchedRecord);
      final plan = CallsLayoutEngine.build(g, visibility(g, hasCalls: true));
      expect(plan.allSlots, contains(CallsLayoutSlot.equipmentHistory));
      expect(plan.allSlots, isNot(contains(CallsLayoutSlot.equipmentActions)));
    });

    test('καταχωρημένος εξοπλισμός χωρίς καμία κλήση → μόνο οι ενέργειες', () {
      final g = _groups(equipment: EquipmentGroupTier.matchedRecord);
      final plan = CallsLayoutEngine.build(g, visibility(g, hasCalls: false));
      expect(plan.allSlots, contains(CallsLayoutSlot.equipmentActions));
      expect(plan.allSlots, isNot(contains(CallsLayoutSlot.equipmentHistory)));
    });

    test('εξοπλισμός εκτός καταλόγου (ελεύθερο κείμενο) → οι ενέργειες', () {
      final g = _groups(equipment: EquipmentGroupTier.freeTextOnly);
      final plan = CallsLayoutEngine.build(g, visibility(g, hasCalls: false));
      expect(plan.allSlots, contains(CallsLayoutSlot.equipmentActions));
    });

    test('χωρίς εξοπλισμό → καμία από τις δύο κάρτες', () {
      final g = _groups(caller: true);
      final plan = CallsLayoutEngine.build(g, visibility(g, hasCalls: false));
      expect(plan.allSlots, isNot(contains(CallsLayoutSlot.equipmentActions)));
      expect(plan.allSlots, isNot(contains(CallsLayoutSlot.equipmentHistory)));
    });

    test(
      'κλειστό «Ιστορικό Εξοπλισμού» από ρυθμίσεις δεν επιστρέφει ως ενέργειες',
      () {
        final g = _groups(equipment: EquipmentGroupTier.matchedRecord);
        final plan = CallsLayoutEngine.build(
          g,
          visibility(g, hasCalls: true, historyCardEnabled: false),
        );
        expect(
          plan.allSlots,
          isNot(contains(CallsLayoutSlot.equipmentActions)),
        );
        expect(
          plan.allSlots,
          isNot(contains(CallsLayoutSlot.equipmentHistory)),
        );
      },
    );

    test('μόνο εξοπλισμός: οι ενέργειες δίπλα στα εργαλεία απομακρυσμένης', () {
      final g = _groups(equipment: EquipmentGroupTier.freeTextOnly);
      final plan = CallsLayoutEngine.build(g, visibility(g, hasCalls: false));
      expect(plan.template, CallsLayoutTemplate.d);
      final firstRow = plan.rows.first.columns
          .map((c) => c.single)
          .whereType<CallsLayoutSlot>()
          .toList();
      expect(
        firstRow,
        containsAll([
          CallsLayoutSlot.remoteTools,
          CallsLayoutSlot.equipmentActions,
        ]),
      );
    });

    test('οι δύο κάρτες δεν συνυπάρχουν ποτέ, σε κανένα πρότυπο', () {
      for (final tier in EquipmentGroupTier.values) {
        for (final hasCalls in [true, false]) {
          for (final phone in [true, false]) {
            for (final caller in [true, false]) {
              final g = _groups(phone: phone, caller: caller, equipment: tier);
              final plan = CallsLayoutEngine.build(
                g,
                visibility(g, hasCalls: hasCalls),
              );
              final slots = plan.allSlots;
              expect(
                slots.contains(CallsLayoutSlot.equipmentHistory) &&
                    slots.contains(CallsLayoutSlot.equipmentActions),
                isFalse,
                reason:
                    'tier=$tier hasCalls=$hasCalls phone=$phone '
                    'caller=$caller',
              );
            }
          }
        }
      }
    });
  });
}
