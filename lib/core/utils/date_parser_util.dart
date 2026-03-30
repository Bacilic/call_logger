import 'package:flutter/material.dart';

/// Αποτέλεσμα από parseSmartInput: είτε εύρος είτε μήνυμα σφάλματος.
typedef DateParseResult = (DateTimeRange? range, String? errorMessage);

/// Έξυπνος parser ημερομηνιών: μία ημέρα ή εύρος με expansion (d/m/y) και validation.
class DateParserUtil {
  DateParserUtil._();

  static const _rangeSeparatorRegex = r'[^0-9/\\\-]+';
  static const _datePartSeparatorRegex = r'[/\\\-]+';

  /// Αναλύει input σε ημερομηνία ή εύρος. Κενό input -> (null, null).
  /// Algorithm: + -> σήμερα; split σε clusters με [^0-9/\\\-]+; πάρε 2 clusters max;
  /// ανά cluster split με /,\,-; expansion 1/2/3 parts; validation; swap αν start > end.
  static DateParseResult parseSmartInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return (null, null);

    // a. Ειδική περίπτωση "+"
    if (trimmed == '+') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return (DateTimeRange(start: today, end: today), null);
    }

    // b. Clusters: split by anything that is NOT digit, /, \, -
    final clusters = trimmed
        .split(RegExp(_rangeSeparatorRegex))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // c. Πρώτα 2 clusters
    if (clusters.isEmpty) return (null, null);
    final cluster1 = clusters[0];
    final cluster2 = clusters.length > 1 ? clusters[1] : null;

    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;

    // d.–e. Parse first cluster
    final first = _parseCluster(cluster1, currentYear, currentMonth);
    if (first.$1 == null) {
      return (null, first.$2 ?? 'Δεν υπάρχει αυτή η μέρα');
    }
    final DateTime start = first.$1!;

    if (cluster2 == null) {
      return (DateTimeRange(start: start, end: start), null);
    }

    final second = _parseCluster(cluster2, currentYear, currentMonth);
    if (second.$1 == null) {
      return (null, second.$2 ?? 'Δεν υπάρχει αυτή η μέρα');
    }
    final DateTime end = second.$1!;

    // g. Swap logic
    final actualStart = start.isAfter(end) ? end : start;
    final actualEnd = start.isAfter(end) ? start : end;
    return (DateTimeRange(start: actualStart, end: actualEnd), null);
  }

  /// Επιστρέφει (DateTime?, errorMessage?).
  /// 3 ψηφία έτους -> "Μη έγκυρο έτος".
  /// Άκυρη ημέρα -> "Δεν υπάρχει αυτή η μέρα".
  static (DateTime?, String?) _parseCluster(
    String cluster,
    int currentYear,
    int currentMonth,
  ) {
    final parts = cluster
        .split(RegExp(_datePartSeparatorRegex))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return (null, null);

    int day;
    int month;
    int year;

    if (parts.length == 1) {
      final d = int.tryParse(parts[0]);
      if (d == null) return (null, 'Δεν υπάρχει αυτή η μέρα');
      day = d;
      month = currentMonth;
      year = currentYear;
    } else if (parts.length == 2) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (d == null || m == null) return (null, 'Δεν υπάρχει αυτή η μέρα');
      day = d;
      month = m;
      year = currentYear;
    } else if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final yearStr = parts[2];
      if (d == null || m == null) return (null, 'Δεν υπάρχει αυτή η μέρα');

      final yearLen = yearStr.length;
      if (yearLen == 3) return (null, 'Μη έγκυρο έτος');

      final y = int.tryParse(yearStr);
      if (y == null) return (null, 'Δεν υπάρχει αυτή η μέρα');

      if (yearLen == 1) {
        year = 2020 + y; // 6 -> 2026
      } else if (yearLen == 2) {
        year = 2000 + y; // 26 -> 2026
      } else if (yearLen == 4) {
        year = y;
      } else {
        return (null, 'Μη έγκυρο έτος');
      }

      day = d;
      month = m;
    } else {
      return (null, 'Δεν υπάρχει αυτή η μέρα');
    }

    // f. Validation: DateTime και έλεγχος ότι δεν διορθώθηκε
    try {
      final res = DateTime(year, month, day);
      if (res.day != day || res.month != month) {
        return (null, 'Δεν υπάρχει αυτή η μέρα');
      }
      return (res, null);
    } catch (_) {
      return (null, 'Δεν υπάρχει αυτή η μέρα');
    }
  }
}
