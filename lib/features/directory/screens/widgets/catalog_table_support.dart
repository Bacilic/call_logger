// Κοινά κομμάτια των πινάκων καταλόγου (Υπάλληλοι, Τμήματα, Εξοπλισμός,
// Κατηγορίες): σχεδίαση γραμμής και ενέργειες πλήκτρων.
//
// Τα πλήκτρα ως μηχανισμός ζουν στο `core/widgets/keyboard_row_navigation.dart`·
// εδώ μένει μόνο ό,τι αφορά τον κατάλογο (τικ, μαζική επεξεργασία, διαγραφή).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Το χρώμα της γραμμής με εστίαση. Ξεχωρίζει από το τικ επιλογής: το τικ
/// βάφει με το «πρωτεύον κοντέινερ», η εστίαση με πιο έντονο πρωτεύον.
Color catalogFocusedRowColor(BuildContext context) =>
    Theme.of(context).colorScheme.primary.withValues(alpha: 0.14);

/// Μετατρέπει μια [DataRow] σε γραμμή του απλού `Table` των πινάκων καταλόγου.
///
/// Το χρώμα της [DataRow] (`color`) σημαίνει **μόνο** «γραμμή με εστίαση»:
/// βάφεται και παίρνει έντονη αριστερή λωρίδα, ώστε να φαίνεται ποια γραμμή
/// ακούει τα πλήκτρα. Το [rowKey] μπαίνει στο πρώτο κελί και επιτρέπει να
/// κυλήσει η οθόνη ώστε να φανεί η γραμμή.
TableRow catalogTableRow(BuildContext context, DataRow dataRow, {Key? rowKey}) {
  final theme = Theme.of(context);
  final dataTableTheme = theme.dataTableTheme;
  final focusColor = dataRow.color?.resolve(const <WidgetState>{});
  final focused = focusColor != null;
  final Color? rowColor = focused
      ? focusColor
      : dataRow.selected
      ? (dataTableTheme.dataRowColor?.resolve({WidgetState.selected}) ??
            theme.colorScheme.primaryContainer.withValues(alpha: 0.3))
      : dataTableTheme.dataRowColor?.resolve({WidgetState.selected});

  // Το «κλικ γραμμής» τρέχει τη στιγμή που πατιέται το ποντίκι, όχι όταν
  // ξεχωρίσει από διπλό κλικ: το Flutter περιμένει ~0,3″ πριν δηλώσει απλό
  // κλικ σε στοιχείο που έχει και διπλό, και η γραμμή έβαφε με καθυστέρηση.
  Widget cellContent(DataCell cell) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if (event.kind == PointerDeviceKind.mouse &&
          event.buttons != kPrimaryMouseButton) {
        return;
      }
      cell.onTap?.call();
    },
    child: InkWell(
      onDoubleTap: cell.onDoubleTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(alignment: Alignment.centerLeft, child: cell.child),
      ),
    ),
  );

  return TableRow(
    decoration: BoxDecoration(
      color: rowColor,
      border: focused
          ? Border(left: BorderSide(color: theme.colorScheme.primary, width: 3))
          : null,
    ),
    children: [
      for (var i = 0; i < dataRow.cells.length; i++)
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: i == 0 && rowKey != null
              ? KeyedSubtree(key: rowKey, child: cellContent(dataRow.cells[i]))
              : cellContent(dataRow.cells[i]),
        ),
    ],
  );
}

/// Enter: με πάνω από ένα τικ ανοίγει τη μαζική επεξεργασία, αλλιώς τη γραμμή
/// με εστίαση. Χωρίς εστίαση και χωρίς πολλαπλά τικ δεν κάνει τίποτα.
void catalogOpenFromKeyboard<T>({
  required List<T> rows,
  required int? focusedIndex,
  required int selectedCount,
  required VoidCallback? onBulkEdit,
  required void Function(T row) onEdit,
}) {
  if (selectedCount > 1 && onBulkEdit != null) {
    onBulkEdit();
    return;
  }
  if (focusedIndex != null && focusedIndex >= 0 && focusedIndex < rows.length) {
    onEdit(rows[focusedIndex]);
  }
}

/// Delete: διαγράφει ό,τι έχει τικ. Αν δεν υπάρχει κανένα τικ, βάζει τικ στη
/// γραμμή με εστίαση και ζητά τη διαγραφή — ο διάλογος επιβεβαίωσης δείχνει
/// πάντα τι θα σβηστεί, και το τικ μένει ορατό αν ο χρήστης ακυρώσει.
void catalogDeleteFromKeyboard({
  required Set<int> selectedIds,
  required int? focusedId,
  required void Function(int id) onToggleSelection,
  required VoidCallback? onRequestDelete,
}) {
  if (onRequestDelete == null) return;
  if (selectedIds.isNotEmpty) {
    onRequestDelete();
    return;
  }
  if (focusedId == null) return;
  onToggleSelection(focusedId);
  onRequestDelete();
}

/// Το id της γραμμής [index] της λίστας [rows], ή `null` όταν η γραμμή δεν
/// υπάρχει (π.χ. η λίστα μίκρυνε και η εστίαση έμεινε πίσω).
int? catalogRowIdAt<T>(List<T> rows, int? index, int? Function(T row) idOf) {
  if (index == null || index < 0 || index >= rows.length) return null;
  return idOf(rows[index]);
}
