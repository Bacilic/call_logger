import 'package:intl/intl.dart';

import '../models/lansweeper_sync_state.dart';

/// Ανάγνωση και ταξινόμηση των γραμμών του πίνακα Ιστορικού κλήσεων, όπως
/// έρχονται από τη βάση. Ο δείκτης στήλης ακολουθεί το `HistorySortColumn`
/// (0 = ημ/νία & ώρα … 8 = συνδέσεις).

/// Καθαρό κείμενο κελιού· κενό για `null`.
String historyRowText(dynamic v) => v?.toString().trim() ?? '';

/// Ονοματεπώνυμο καλούντα, ή «—» όταν λείπει.
String historyCallerDisplay(Map<String, dynamic> row) {
  final first = row['user_first_name'] as String? ?? '';
  final last = row['user_last_name'] as String? ?? '';
  final combined = '$first $last'.trim();
  return combined.isEmpty ? '—' : combined;
}

/// Η στήλη «Περιγραφή»: το ένα και μοναδικό κείμενο της κλήσης (v43).
String historyNotesDisplay(Map<String, dynamic> row) =>
    historyRowText(row['issue']);

/// Οι ενδείξεις έρχονται από SQL ως 1/0 — ανεκτικό και σε bool/κείμενο.
bool historyFlagIsSet(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  return v?.toString().trim() == '1';
}

final DateFormat _callDateParse = DateFormat('yyyy-MM-dd');
final DateFormat _callDateTimeParse = DateFormat('yyyy-MM-dd HH:mm');

/// Ανάλυση ημ/νίας & ώρας όπως αποθηκεύονται στη βάση (date: yyyy-MM-dd, time: HH:mm).
DateTime? parseHistoryCallDateTime(Map<String, dynamic> row) {
  final d = historyRowText(row['date']);
  final t = historyRowText(row['time']);
  if (d.isEmpty) return null;
  try {
    if (t.isEmpty) {
      return _callDateParse.parseStrict(d);
    }
    return _callDateTimeParse.parseStrict('$d $t');
  } catch (_) {
    return null;
  }
}

/// Τιμή για σύγκριση ταξινόμησης ανά ευρετήριο στήλης (0..8).
Comparable<Object> historyCallSortValue(
  Map<String, dynamic> row,
  int columnIndex,
) {
  switch (columnIndex) {
    case 0:
      final dt = parseHistoryCallDateTime(row);
      return dt?.millisecondsSinceEpoch ?? -1;
    case 1:
      return historyCallerDisplay(row);
    case 2:
      return row['user_phone']?.toString().trim() ?? '';
    case 3:
      return historyRowText(row['user_department']);
    case 4:
      return historyRowText(row['equipment_code']);
    case 5:
      return historyRowText(row['category']);
    case 6:
      return historyNotesDisplay(row);
    case 7:
      final dur = row['duration'];
      if (dur == null) return -1;
      return dur is int ? dur : int.tryParse(dur?.toString() ?? '') ?? -1;
    case 8:
      // Πρώτα όσες άφησαν ουρά — μετράει το πλήθος των ορατών σημάτων.
      final state = LansweeperSyncState.normalize(
        historyRowText(row['lansweeper_state']),
      );
      return (historyFlagIsSet(row['has_open_task']) ? 1 : 0) +
          (state == LansweeperSyncState.unsent ? 0 : 1);
    default:
      return '';
  }
}

/// Νέα λίστα ταξινομημένη κατά τη στήλη· η αρχική δεν αλλάζει.
List<Map<String, dynamic>> sortHistoryCallRows(
  List<Map<String, dynamic>> rows,
  int columnIndex,
  bool ascending,
) {
  final list = List<Map<String, dynamic>>.from(rows);
  list.sort((a, b) {
    final va = historyCallSortValue(a, columnIndex);
    final vb = historyCallSortValue(b, columnIndex);
    final c = va.compareTo(vb);
    return ascending ? c : -c;
  });
  return list;
}
