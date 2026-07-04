import '../../../core/config/calls_layout_config.dart';
import 'calls_layout_template.dart';

/// Identifiers for widgets placed by [CallsLayoutEngine].
enum CallsLayoutSlot {
  /// Notes sticky field (phone control group).
  ///
  /// ΚΑΝΟΝΑΣ: το τικ «Εκκρεμότητα» ζει ΜΟΝΙΜΑ μέσα στο χαρτί σημειώσεων
  /// (βλ. NotesStickyField) γιατί εκκρεμότητα δημιουργείται μόνο από
  /// σημειώσεις — καμία αναδιάταξη δεν επιτρέπεται να τα χωρίσει.
  notes,

  /// Κατηγορία + χρονόμετρο + κουμπί «Καταγραφή» (phone control group).
  ///
  /// ΚΑΝΟΝΑΣ: τα τρία αυτά στοιχεία είναι μία λειτουργική ομάδα και
  /// αποδίδονται ΠΑΝΤΑ στην ίδια γραμμή (βλ. _CategoryTimerSubmitRow).
  categoryPending,

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

/// Αποφασίζει αν οι στήλες μιας γραμμής στοιβάζονται κάθετα αντί για οριζόντιο πλέγμα.
bool callsLayoutShouldStackColumns({
  required double contentWidth,
  required CallsLayoutPlan plan,
  double columnGap = 16,
}) {
  if (contentWidth < callsLayoutNarrowViewportBreakpoint) return true;
  for (final row in plan.rows) {
    final colCount = row.columns.where((c) => !c.isEmpty).length;
    if (colCount <= 1) continue;
    final gutters = (colCount - 1) * columnGap;
    final perCol = (contentWidth - gutters) / colCount;
    if (perCol < callsLayoutMinColumnWidth) return true;
  }
  return false;
}
