/// Μοντέλο φίλτρων για τον πίνακα ελέγχου στατιστικών κλήσεων (χωρίς εξαρτήσεις από providers/repository).
class DashboardFilterModel {
  const DashboardFilterModel({
    this.keyword = '',
    this.dateFrom,
    this.dateTo,
    this.department,
    this.userName,
    this.equipmentCode,
    this.topN = 5,
  });

  final String keyword;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? department;
  final String? userName;
  final String? equipmentCode;
  final int topN;

  DashboardFilterModel copyWith({
    String? keyword,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? department,
    String? userName,
    String? equipmentCode,
    int? topN,
    bool clearDateRange = false,
    bool clearDepartment = false,
    bool clearUserName = false,
    bool clearEquipmentCode = false,
  }) {
    return DashboardFilterModel(
      keyword: keyword ?? this.keyword,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      department: clearDepartment ? null : (department ?? this.department),
      userName: clearUserName ? null : (userName ?? this.userName),
      equipmentCode: clearEquipmentCode
          ? null
          : (equipmentCode ?? this.equipmentCode),
      topN: topN ?? this.topN,
    );
  }

  /// `dateFrom` / `dateTo` as `yyyy-MM-dd` for SQL.
  String? get dateFromSql => dateFrom != null ? _formatDate(dateFrom!) : null;

  String? get dateToSql => dateTo != null ? _formatDate(dateTo!) : null;

  static String _formatDate(DateTime d) {
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Calendar day (strip time).
  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Previous period of same inclusive length when both dateFrom and dateTo are set.
  /// Returns null if a bound is missing or the range is inverted.
  ({DateTime start, DateTime end})? get previousComparisonRangeInclusive {
    if (dateFrom == null || dateTo == null) return null;
    final s = dayOnly(dateFrom!);
    final e = dayOnly(dateTo!);
    if (e.isBefore(s)) return null;
    final inclusiveDays = e.difference(s).inDays + 1;
    final prevEnd = s.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: inclusiveDays - 1));
    return (start: prevStart, end: prevEnd);
  }

  static String formatDisplayDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Κείμενο για τίτλο KPI «Συνολικές κλήσεις» ανάλογα με το εύρος φίλτρου.
  String kpiTotalCallsRangeTitle({DateTime? now}) {
    final n = now != null ? dayOnly(now) : dayOnly(DateTime.now());
    if (dateFrom == null && dateTo == null) {
      return String.fromCharCodes(const <int>[
        0x038C,
        0x03BB,
        0x03B5,
        0x03C2,
        0x20,
        0x03BF,
        0x03B9,
        0x20,
        0x03B7,
        0x03BC,
        0x03B5,
        0x03C1,
        0x03BF,
        0x03BC,
        0x03B7,
        0x03BD,
        0x03AF,
        0x03B5,
        0x03C2,
      ]);
    }
    if (dateFrom != null && dateTo != null) {
      final s = dayOnly(dateFrom!);
      final e = dayOnly(dateTo!);
      if (s == e) {
        return s == n ? 'Σήμερα' : formatDisplayDate(s);
      }
      final days = e.difference(s).inDays + 1;
      if (days == 7 && e == n) return 'Τελευταία εβδομάδα';
      if (days == 30 && e == n) return 'Τελευταίες 30 ημέρες';
      return '${formatDisplayDate(s)} – ${formatDisplayDate(e)}';
    }
    if (dateFrom != null) return 'από ${formatDisplayDate(dayOnly(dateFrom!))}';
    return 'έως ${formatDisplayDate(dayOnly(dateTo!))}';
  }

  /// Μικρή περιγραφή περιόδου σύγκρισης για υπότιτλους KPI.
  String kpiComparisonRangeHint({DateTime? now}) {
    final n = now != null ? dayOnly(now) : dayOnly(DateTime.now());
    final prev = previousComparisonRangeInclusive;
    if (prev != null) {
      if (prev.start == prev.end) {
        return 'προηγ. ημέρα (${formatDisplayDate(prev.start)})';
      }
      return 'προηγ. εύρος (${formatDisplayDate(prev.start)}–${formatDisplayDate(prev.end)})';
    }
    final anchor = dayOnly(dateTo ?? dateFrom ?? n);
    final y = anchor.subtract(const Duration(days: 1));
    return 'προηγ. ημέρα (${formatDisplayDate(y)})';
  }
}
