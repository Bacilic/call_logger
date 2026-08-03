// Φράσεις για τις ιστορικές συνδέσεις ενός τηλεφώνου ή εξοπλισμού: πόσες
// είναι και πότε ήταν η τελευταία.
//
// Ζουν εδώ και όχι μέσα στα repositories ώστε η διατύπωση να γράφεται μία
// φορά — τηλέφωνα και εξοπλισμός έλεγαν τα ίδια ελληνικά χωριστά — και να
// ελέγχεται χωρίς βάση δεδομένων.

import 'package:intl/intl.dart';

final DateFormat _stampFormat = DateFormat('dd/MM/yyyy');

/// «2 εκκρεμότητες (τελευταία 12/06/2026)».
String taskHistoryLabel(int count, {DateTime? lastUsedAt}) => _withLastUsed(
  count == 1 ? '1 εκκρεμότητα' : '$count εκκρεμότητες',
  lastUsedAt,
);

/// «5 κλήσεις ιστορικού (τελευταία 12/06/2026)».
String callHistoryLabel(int count, {DateTime? lastUsedAt}) => _withLastUsed(
  count == 1 ? '1 κλήση ιστορικού' : '$count κλήσεις ιστορικού',
  lastUsedAt,
);

/// Χωρίς χρονοσήμανση η φράση μένει όπως ήταν: καλύτερα να μη λέμε τίποτα
/// παρά να δείξουμε ημερομηνία για εγγραφές που δεν κατέγραψαν ποτέ πότε έγιναν.
String _withLastUsed(String base, DateTime? at) =>
    at == null ? base : '$base (τελευταία ${_stampFormat.format(at)})';
