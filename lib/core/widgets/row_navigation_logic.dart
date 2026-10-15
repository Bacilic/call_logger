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
