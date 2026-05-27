/// Προκαθορισμένο εύρος ημερομηνιών για αναφορές εκκρεμοτήτων.
enum TaskAnalyticsDatePreset {
  today,
  last7,
  last30,

  /// Από παλαιότερη έως νεότερη ημερομηνία δημιουργίας εκκρεμότητας.
  all,
  custom;

  static const TaskAnalyticsDatePreset defaultPreset =
      TaskAnalyticsDatePreset.all;

  String get storageValue => name;

  static TaskAnalyticsDatePreset? fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final p in TaskAnalyticsDatePreset.values) {
      if (p.storageValue == raw) return p;
    }
    return null;
  }

  static DateTime dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Εύρος ημερομηνιών για preset (χωρίς `all` — χρειάζεται [creationSpan]).
  static ({DateTime start, DateTime end}) dateRangeFor(
    TaskAnalyticsDatePreset preset, {
    DateTime? now,
    DateTime? customFrom,
    DateTime? customTo,
    required ({DateTime start, DateTime end}) creationSpan,
  }) {
    switch (preset) {
      case TaskAnalyticsDatePreset.all:
        return creationSpan;
      case TaskAnalyticsDatePreset.custom:
        if (customFrom == null || customTo == null) {
          return creationSpan;
        }
        return (
          start: dayOnly(customFrom),
          end: dayOnly(customTo),
        );
      case TaskAnalyticsDatePreset.today:
      case TaskAnalyticsDatePreset.last7:
      case TaskAnalyticsDatePreset.last30:
        final anchor = now ?? DateTime.now();
        final end = dayOnly(anchor);
        final inclusiveDays = switch (preset) {
          TaskAnalyticsDatePreset.today => 1,
          TaskAnalyticsDatePreset.last7 => 7,
          TaskAnalyticsDatePreset.last30 => 30,
          _ => 1,
        };
        final start = end.subtract(Duration(days: inclusiveDays - 1));
        return (start: start, end: end);
    }
  }

  /// Αναγνώριση preset από τρέχον εύρος (null = custom).
  static TaskAnalyticsDatePreset? detect({
    required DateTime start,
    required DateTime end,
    required ({DateTime start, DateTime end}) creationSpan,
    DateTime? now,
  }) {
    final s = dayOnly(start);
    final e = dayOnly(end);
    final spanStart = dayOnly(creationSpan.start);
    final spanEnd = dayOnly(creationSpan.end);
    if (s == spanStart && e == spanEnd) {
      return TaskAnalyticsDatePreset.all;
    }
    final n = dayOnly(now ?? DateTime.now());
    if (s == e) {
      return s == n ? TaskAnalyticsDatePreset.today : null;
    }
    final days = e.difference(s).inDays + 1;
    if (days == 7 && e == n) return TaskAnalyticsDatePreset.last7;
    if (days == 30 && e == n) return TaskAnalyticsDatePreset.last30;
    return null;
  }

  int? get presetDayCount => switch (this) {
        TaskAnalyticsDatePreset.today => 1,
        TaskAnalyticsDatePreset.last7 => 7,
        TaskAnalyticsDatePreset.last30 => 30,
        _ => null,
      };
}
