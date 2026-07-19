import '../../../core/models/calls_screen_cards_visibility.dart';
import 'calls_field_groups.dart';
import 'calls_layout_plan.dart';
import 'calls_layout_template.dart';

/// Visibility + data gates applied when building a layout plan.
class CallsLayoutVisibility {
  const CallsLayoutVisibility({
    required this.showUserCard,
    required this.showMapCard,
    required this.showEmployeeRecentCard,
    required this.showEquipmentRecentPanel,
    required this.showGlobalRecentCard,
    required this.showRemoteTools,
    required this.hasCallerHistoryData,
    required this.hasEquipmentHistoryData,
  });

  final bool showUserCard;
  final bool showMapCard;
  final bool showEmployeeRecentCard;
  final bool showEquipmentRecentPanel;
  final bool showGlobalRecentCard;
  final bool showRemoteTools;
  final bool hasCallerHistoryData;
  final bool hasEquipmentHistoryData;

  factory CallsLayoutVisibility.from({
    required CallsScreenCardsVisibility cards,
    required CallsFieldGroups groups,
    required bool showRemoteTools,
    required bool hasCallerHistoryData,
    required bool hasEquipmentHistoryData,
    bool? showGlobalRecentCard,
  }) {
    return CallsLayoutVisibility(
      showUserCard: cards.showUserCard && groups.isCallerGroupActive,
      showMapCard: cards.showMapCard && groups.isMapActive,
      showEmployeeRecentCard:
          cards.showEmployeeRecentCard &&
          groups.isCallerGroupActive &&
          hasCallerHistoryData,
      showEquipmentRecentPanel:
          cards.showEquipmentRecentPanel &&
          groups.equipmentTier == EquipmentGroupTier.matchedRecord &&
          hasEquipmentHistoryData,
      showGlobalRecentCard:
          showGlobalRecentCard ?? cards.showGlobalRecentCard,
      showRemoteTools: showRemoteTools && groups.isEquipmentGroupActive,
      hasCallerHistoryData: hasCallerHistoryData,
      hasEquipmentHistoryData: hasEquipmentHistoryData,
    );
  }
}

/// Pure layout engine — maps active groups + visibility to row/column/slot plan.
class CallsLayoutEngine {
  const CallsLayoutEngine._();

  static CallsLayoutPlan build(
    CallsFieldGroups groups,
    CallsLayoutVisibility visibility,
  ) {
    final plan = switch (groups.template) {
      CallsLayoutTemplate.a => _templateA(groups, visibility),
      CallsLayoutTemplate.b => _templateB(groups, visibility),
      CallsLayoutTemplate.c => _templateC(groups, visibility),
      CallsLayoutTemplate.d => _templateD(groups, visibility),
    };
    return _applyKRules(plan, visibility);
  }

  static CallsLayoutPlan _templateA(
    CallsFieldGroups groups,
    CallsLayoutVisibility v,
  ) {
    if (groups.isPhoneOnlyTemplateA) {
      return _templateAPhoneOnly(groups, v);
    }
    return _templateAFull(groups, v);
  }

  /// Πρότυπο Α #1 — μόνο τηλέφωνο (`1- τηλέφωνο.png`).
  static CallsLayoutPlan _templateAPhoneOnly(
    CallsFieldGroups groups,
    CallsLayoutVisibility v,
  ) {
    final rows = <CallsLayoutRow>[];

    if (groups.isPhoneGroupActive) {
      rows.add(
        CallsLayoutRow([
          CallsLayoutColumn.singleSlot(CallsLayoutSlot.notes),
        ]),
      );
    }

    if (groups.isPhoneGroupActive) {
      // Κατηγορία+χρονόμετρο+Καταγραφή = ενιαία γραμμή (ένα slot).
      final actionCols = <CallsLayoutColumn>[
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.categoryPending),
        if (v.showEquipmentRecentPanel)
          CallsLayoutColumn.singleSlot(CallsLayoutSlot.equipmentHistory),
      ];
      rows.add(CallsLayoutRow(actionCols));
    }

    final infoCols = _templateAInfoColumns(v);
    if (infoCols.any((c) => !c.isEmpty)) {
      rows.add(CallsLayoutRow(infoCols));
    }

    return CallsLayoutPlan(template: CallsLayoutTemplate.a, rows: rows);
  }

  /// Πρότυπο Α πλήρες — σημειώσεις μοιράζονται γραμμή 2 με ενέργειες/εξοπλισμό.
  static CallsLayoutPlan _templateAFull(
    CallsFieldGroups groups,
    CallsLayoutVisibility v,
  ) {
    final row2Cols = <CallsLayoutColumn>[
      if (groups.isPhoneGroupActive)
        CallsLayoutColumn.stack([
          CallsLayoutSlot.notes,
          CallsLayoutSlot.categoryPending,
        ]),
      if (v.showRemoteTools)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.remoteTools),
      if (v.showEquipmentRecentPanel)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.equipmentHistory),
    ];

    final rows = <CallsLayoutRow>[
      if (row2Cols.any((c) => !c.isEmpty)) CallsLayoutRow(row2Cols),
      if (_templateAInfoColumns(v).any((c) => !c.isEmpty))
        CallsLayoutRow(_templateAInfoColumns(v)),
    ];

    return CallsLayoutPlan(template: CallsLayoutTemplate.a, rows: rows);
  }

  static List<CallsLayoutColumn> _templateAInfoColumns(
    CallsLayoutVisibility v,
  ) {
    return [
      CallsLayoutColumn.stack([
        if (v.showUserCard) CallsLayoutSlot.callerCard,
        if (v.showEmployeeRecentCard) CallsLayoutSlot.callerHistory,
      ]),
      if (v.showMapCard) CallsLayoutColumn.singleSlot(CallsLayoutSlot.map),
      if (v.showGlobalRecentCard)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.globalRecent),
    ];
  }

  static CallsLayoutPlan _templateB(
    CallsFieldGroups groups,
    CallsLayoutVisibility v,
  ) {
    // Χωρίς τηλέφωνο: remote + χάρτης + καλούντας στην 1η γραμμή.
    // Το ιστορικό εξοπλισμού ΔΕΝ μπαίνει εδώ — 4η στήλη ανάγκαζε στοίβα
    // (ίσος διαμοιρασμός 380px) ακόμα και σε φαρδιά παράθυρα.
    final rowInfo = CallsLayoutRow([
      if (v.showRemoteTools)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.remoteTools),
      if (v.showMapCard) CallsLayoutColumn.singleSlot(CallsLayoutSlot.map),
      if (v.showUserCard) CallsLayoutColumn.singleSlot(CallsLayoutSlot.callerCard),
    ]);

    final rowHistory = CallsLayoutRow([
      if (v.showEquipmentRecentPanel)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.equipmentHistory),
      if (v.showEmployeeRecentCard)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.callerHistory),
      if (v.showGlobalRecentCard)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.globalRecent),
    ]);

    return CallsLayoutPlan(
      template: CallsLayoutTemplate.b,
      rows: [rowInfo, rowHistory].where((r) => !r.isEmpty).toList(),
    );
  }

  static CallsLayoutPlan _templateC(
    CallsFieldGroups groups,
    CallsLayoutVisibility v,
  ) {
    final cols = <CallsLayoutColumn>[
      CallsLayoutColumn.stack([
        if (v.showUserCard) CallsLayoutSlot.callerCard,
        if (v.showEmployeeRecentCard) CallsLayoutSlot.callerHistory,
      ]),
      if (v.showMapCard) CallsLayoutColumn.singleSlot(CallsLayoutSlot.map),
      if (v.showGlobalRecentCard)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.globalRecent),
    ];

    return CallsLayoutPlan(
      template: CallsLayoutTemplate.c,
      rows: [CallsLayoutRow(cols)],
    );
  }

  static CallsLayoutPlan _templateD(
    CallsFieldGroups groups,
    CallsLayoutVisibility v,
  ) {
    // Remote tools στην 1η γραμμή μαζί με χάρτη/ιστορικό εξοπλισμού.
    final row2 = CallsLayoutRow([
      if (v.showRemoteTools)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.remoteTools),
      if (v.showMapCard) CallsLayoutColumn.singleSlot(CallsLayoutSlot.map),
      if (v.showEquipmentRecentPanel)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.equipmentHistory),
    ]);

    final row3Cols = <CallsLayoutColumn>[
      if (v.showGlobalRecentCard)
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.globalRecent),
    ];

    return CallsLayoutPlan(
      template: CallsLayoutTemplate.d,
      rows: [
        if (!row2.isEmpty) row2,
        if (row3Cols.any((c) => !c.isEmpty)) CallsLayoutRow(row3Cols),
      ],
    );
  }

  /// K1–K5: drop empty columns/rows; dedupe categoryActions in template A col2.
  static CallsLayoutPlan _applyKRules(
    CallsLayoutPlan plan,
    CallsLayoutVisibility visibility,
  ) {
    final cleanedRows = <CallsLayoutRow>[];

    for (final row in plan.rows) {
      final cols = row.columns
          .map(_cleanColumn)
          .where((c) => !c.isEmpty)
          .toList();
      if (cols.isEmpty) continue;
      cleanedRows.add(CallsLayoutRow(cols));
    }

    // K2: empty rows already removed above.

    return CallsLayoutPlan(template: plan.template, rows: cleanedRows);
  }

  static CallsLayoutColumn _cleanColumn(CallsLayoutColumn col) {
    final slots = col.slots.toSet().toList();
    if (slots.isEmpty) return const CallsLayoutColumn();
    if (col.single != null) {
      return CallsLayoutColumn.singleSlot(slots.first);
    }
    return CallsLayoutColumn.stack(slots);
  }
}
