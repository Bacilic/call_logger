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

/// Ελάχιστο χρήσιμο πλάτος στήλης για απόφαση στοίβας (όχι υποχρεωτικά ίσο
/// με το max cap της κάρτας — το TightVNC είναι στενό).
double callsLayoutColumnMinWidth(CallsLayoutColumn column) {
  final slots = column.slots;
  if (slots.isEmpty) return 0;
  if (slots.length == 1) {
    return switch (slots.single) {
      CallsLayoutSlot.remoteTools => 180,
      CallsLayoutSlot.map => 336,
      CallsLayoutSlot.callerCard => 280,
      CallsLayoutSlot.notes => 420,
      CallsLayoutSlot.categoryPending => 420,
      CallsLayoutSlot.equipmentHistory => 320,
      CallsLayoutSlot.callerHistory => 320,
      CallsLayoutSlot.globalRecent => 320,
    };
  }
  // Στοίβα μέσα στη στήλη (π.χ. notes+category): το μεγαλύτερο ελάχιστο.
  return slots
      .map((s) => callsLayoutColumnMinWidth(CallsLayoutColumn.singleSlot(s)))
      .fold<double>(0, (a, b) => a > b ? a : b);
}

/// Αποφασίζει αν οι στήλες μιας γραμμής στοιβάζονται κάθετα.
bool callsLayoutShouldStackRow({
  required double contentWidth,
  required CallsLayoutRow row,
  double columnGap = 16,
}) {
  if (contentWidth < callsLayoutNarrowViewportBreakpoint) return true;

  final cols = row.columns.where((c) => !c.isEmpty).toList();
  if (cols.length <= 1) return false;

  final gutters = (cols.length - 1) * columnGap;
  final needed =
      cols.map(callsLayoutColumnMinWidth).fold<double>(0, (a, b) => a + b) +
          gutters;
  return contentWidth < needed;
}

/// Αποφασίζει αν κάποια γραμμή του πλάνου στοιβάζεται (για tests / συμβατότητα).
bool callsLayoutShouldStackColumns({
  required double contentWidth,
  required CallsLayoutPlan plan,
  double columnGap = 16,
}) {
  if (contentWidth < callsLayoutNarrowViewportBreakpoint) return true;
  for (final row in plan.rows) {
    if (callsLayoutShouldStackRow(
      contentWidth: contentWidth,
      row: row,
      columnGap: columnGap,
    )) {
      return true;
    }
  }
  return false;
}
