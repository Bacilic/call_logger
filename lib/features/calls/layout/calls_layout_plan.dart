import 'calls_layout_template.dart';

/// Identifiers for widgets placed by [CallsLayoutEngine].
enum CallsLayoutSlot {
  /// Notes sticky field (phone control group).
  notes,

  /// Category field + pending toggle + timer (phone control group).
  categoryPending,

  /// Status bar, submit, Εκκαθάριση (phone control group).
  submitActions,

  /// Remote connection buttons (equipment group).
  remoteTools,

  /// Equipment recent calls panel (matched equipment only).
  equipmentHistory,

  /// User info card (caller group).
  callerCard,

  /// Employee recent calls list (caller group).
  callerHistory,

  /// Mini map card.
  map,

  /// Global recent calls (Τελευταίες Κλήσεις).
  globalRecent,
}

/// Vertical stack inside a column (K3).
class CallsLayoutStack {
  const CallsLayoutStack(this.slots);

  final List<CallsLayoutSlot> slots;

  bool get isEmpty => slots.isEmpty;
}

/// One column in a layout row.
class CallsLayoutColumn {
  const CallsLayoutColumn({this.stack = const [], this.single});

  /// Stacked slots top-to-bottom (K3).
  final List<CallsLayoutSlot> stack;

  /// Single slot occupying the column (mutually exclusive with non-empty [stack]).
  final CallsLayoutSlot? single;

  List<CallsLayoutSlot> get slots {
    if (single != null) return [single!];
    return stack;
  }

  bool get isEmpty => slots.isEmpty;

  factory CallsLayoutColumn.stack(List<CallsLayoutSlot> slots) =>
      CallsLayoutColumn(stack: slots);

  factory CallsLayoutColumn.singleSlot(CallsLayoutSlot slot) =>
      CallsLayoutColumn(single: slot);
}

/// One horizontal row in expanded layout.
class CallsLayoutRow {
  const CallsLayoutRow(this.columns);

  final List<CallsLayoutColumn> columns;

  bool get isEmpty => columns.every((c) => c.isEmpty);
}

/// Full layout plan for expanded mode.
class CallsLayoutPlan {
  const CallsLayoutPlan({
    required this.template,
    required this.rows,
  });

  final CallsLayoutTemplate template;
  final List<CallsLayoutRow> rows;

  /// Flat ordered slot list (for tests / debugging).
  List<CallsLayoutSlot> get allSlots => [
        for (final row in rows)
          for (final col in row.columns) ...col.slots,
      ];
}
