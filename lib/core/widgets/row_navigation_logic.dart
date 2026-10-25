// Ο κανόνας κίνησης με τα πλήκτρα σε πίνακα γραμμών — καθαρή λογική, χωρίς UI.
//
// Ζει στο core γιατί δεν ξέρει τίποτα για υπαλλήλους ή τμήματα: το ίδιο πρέπει
// να δουλεύει σε κάθε πίνακα της εφαρμογής (κατάλογοι, ιστορικά).

import 'package:flutter/services.dart';

/// Γραμμές που διανύει ένα Page Up/Down όταν ο πίνακας δεν έχει σελίδες.
const int kDefaultRowPageStep = 10;

/// Η γραμμή που θα εστιαστεί μετά από το πλήκτρο [key], ή `null` όταν το
/// πλήκτρο δεν είναι πλήκτρο κίνησης (ή δεν υπάρχουν γραμμές).
///
/// - ↓/↑: μία γραμμή. Χωρίς εστιασμένη γραμμή, το ↓ ξεκινά από την πρώτη και
///   το ↑ από την τελευταία.
/// - Page Down/Up: [pageStep] γραμμές. Home/End: πρώτη/τελευταία.
/// - Το αποτέλεσμα μένει πάντα μέσα στο `0..count-1`.
int? rowIndexAfterKey({
  required LogicalKeyboardKey key,
  required int? current,
  required int count,
  int pageStep = kDefaultRowPageStep,
}) {
  if (count <= 0) return null;
  final last = count - 1;
  final from = current?.clamp(0, last);

  if (key == LogicalKeyboardKey.arrowDown) {
    return from == null ? 0 : (from + 1).clamp(0, last);
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    return from == null ? last : (from - 1).clamp(0, last);
  }
  if (key == LogicalKeyboardKey.pageDown) {
    return from == null ? 0 : (from + pageStep).clamp(0, last);
  }
  if (key == LogicalKeyboardKey.pageUp) {
    return from == null ? last : (from - pageStep).clamp(0, last);
  }
  if (key == LogicalKeyboardKey.home) return 0;
  if (key == LogicalKeyboardKey.end) return last;
  return null;
}

/// Η θέση κύλισης που κάνει ολόκληρη ορατή τη γραμμή [index], σε λίστα όπου
/// όλες οι γραμμές έχουν το ίδιο ύψος [rowExtent].
///
/// Κυλά το ελάχιστο: αν η γραμμή φαίνεται ήδη, η θέση [currentOffset] δεν
/// αλλάζει. Έτσι δουλεύει και για γραμμές που η λίστα δεν έχει χτίσει ακόμη
/// — η θέση τους βγαίνει από το νούμερο, χωρίς να χρειάζεται η ίδια η γραμμή.
double scrollOffsetRevealingRow({
  required int index,
  required double rowExtent,
  required double viewportExtent,
  required double currentOffset,
}) {
  final top = index * rowExtent;
  final bottom = top + rowExtent;
  if (top < currentOffset) return top;
  if (bottom > currentOffset + viewportExtent) {
    return bottom - viewportExtent;
  }
  return currentOffset;
}

/// Πόσες γραμμές ύψους [rowExtent] χωρούν ολόκληρες σε [viewportExtent] — το
/// βήμα του Page Up/Down σε λίστα χωρίς σελίδες. Τουλάχιστον μία.
int rowsFittingViewport({
  required double viewportExtent,
  required double rowExtent,
}) {
  if (rowExtent <= 0) return 1;
  final fitting = (viewportExtent / rowExtent).floor();
  return fitting < 1 ? 1 : fitting;
}

/// Η πρώτη γραμμή της σελίδας που πρέπει να φαίνεται ώστε η [focusedRow] να
/// είναι ορατή. Αν είναι ήδη μέσα στη σελίδα που αρχίζει από [currentStart],
/// η σελίδα δεν αλλάζει.
int pageStartShowingRow({
  required int focusedRow,
  required int pageSize,
  required int currentStart,
}) {
  if (focusedRow >= currentStart && focusedRow < currentStart + pageSize) {
    return currentStart;
  }
  return (focusedRow ~/ pageSize) * pageSize;
}

/// Η πρώτη γραμμή της τελευταίας σελίδας ([count] γραμμές, [pageSize] ανά
/// σελίδα). Χωρίς γραμμές, `0`.
int lastPageStart({required int count, required int pageSize}) {
  if (count <= 0) return 0;
  return ((count - 1) ~/ pageSize) * pageSize;
}

/// Η αρχή της προηγούμενης σελίδας από εκείνη που αρχίζει στο [start]· δεν
/// πέφτει κάτω από την πρώτη ούτε πάνω από την τελευταία σελίδα.
int previousPageStart({
  required int start,
  required int count,
  required int pageSize,
}) {
  return (start - pageSize).clamp(
    0,
    lastPageStart(count: count, pageSize: pageSize),
  );
}

/// Η αρχή της επόμενης σελίδας, ή `null` όταν η σελίδα στο [start] είναι η
/// τελευταία.
int? nextPageStart({
  required int start,
  required int count,
  required int pageSize,
}) {
  final next = start + pageSize;
  return next < count ? next : null;
}
