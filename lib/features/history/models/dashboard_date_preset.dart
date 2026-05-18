import 'dashboard_filter_model.dart';

/// Προκαθορισμένο εύρος ημερομηνιών για τον πίνακα στατιστικών κλήσεων.
enum DashboardDatePreset {
  today,
  last7,
  last30,
  all,
  custom;

  static const DashboardDatePreset defaultPreset = DashboardDatePreset.today;

  String get storageValue => name;

  static DashboardDatePreset? fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final p in DashboardDatePreset.values) {
      if (p.storageValue == raw) return p;
    }
    return null;
  }

  /// Αναγνώριση preset από τρέχον φίλτρο (null = custom / μη τυπικό εύρος).
  static DashboardDatePreset? detect(DashboardFilterModel filter, {DateTime? now}) {
    final n = now != null
        ? DashboardFilterModel.dayOnly(now)
        : DashboardFilterModel.dayOnly(DateTime.now());
    if (filter.dateFrom == null && filter.dateTo == null) {
      return DashboardDatePreset.all;
    }
    if (filter.dateFrom == null || filter.dateTo == null) {
      return DashboardDatePreset.custom;
    }
    final s = DashboardFilterModel.dayOnly(filter.dateFrom!);
    final e = DashboardFilterModel.dayOnly(filter.dateTo!);
    if (s == e) {
      return s == n ? DashboardDatePreset.today : DashboardDatePreset.custom;
    }
    final days = e.difference(s).inDays + 1;
    if (days == 7 && e == n) return DashboardDatePreset.last7;
    if (days == 30 && e == n) return DashboardDatePreset.last30;
    return DashboardDatePreset.custom;
  }

  /// Εφαρμογή preset σε ημερομηνίες φίλτρου.
  static ({DateTime? dateFrom, DateTime? dateTo}) dateRangeFor(
    DashboardDatePreset preset, {
    DateTime? now,
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    switch (preset) {
      case DashboardDatePreset.all:
        return (dateFrom: null, dateTo: null);
      case DashboardDatePreset.custom:
        if (customFrom == null || customTo == null) {
          return (dateFrom: null, dateTo: null);
        }
        return (
          dateFrom: DashboardFilterModel.dayOnly(customFrom),
          dateTo: DashboardFilterModel.dayOnly(customTo),
        );
      case DashboardDatePreset.today:
      case DashboardDatePreset.last7:
      case DashboardDatePreset.last30:
        final anchor = now ?? DateTime.now();
        final end = DashboardFilterModel.dayOnly(anchor);
        final inclusiveDays = switch (preset) {
          DashboardDatePreset.today => 1,
          DashboardDatePreset.last7 => 7,
          DashboardDatePreset.last30 => 30,
          _ => 1,
        };
        final start = end.subtract(Duration(days: inclusiveDays - 1));
        return (dateFrom: start, dateTo: end);
    }
  }

  static DashboardFilterModel applyToFilter(
    DashboardFilterModel base,
    DashboardDatePreset preset, {
    DateTime? now,
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    final range = dateRangeFor(
      preset,
      now: now,
      customFrom: customFrom,
      customTo: customTo,
    );
    return base.copyWith(
      dateFrom: range.dateFrom,
      dateTo: range.dateTo,
      clearDateRange: range.dateFrom == null && range.dateTo == null,
    );
  }
}
