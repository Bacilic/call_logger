/// Καταστάσεις αποτελέσματος προγραμματισμένου αντιγράφου (τυπικά string στη ρύθμιση).
abstract final class BackupScheduleStatus {
  static const String success = 'success';
  static const String failed = 'failed';
  static const String missed = 'missed';
  static const String none = 'none';

  static String normalize(String? raw) {
    final s = raw?.trim() ?? '';
    switch (s) {
      case success:
      case failed:
      case missed:
      case none:
        return s;
      default:
        return none;
    }
  }
}

/// Parsing και βοηθητικά για εβδομαδιαίο χρονοδιάγραμμα (weekday = DateTime.weekday).
class BackupScheduleUtils {
  BackupScheduleUtils._();

  /// Επαληθεύει λίστα ημερών 1–7 χωρίς διπλότυπα.
  static List<int> normalizeDays(List<int> raw) {
    final out = <int>{};
    for (final d in raw) {
      if (d >= 1 && d <= 7) out.add(d);
    }
    final list = out.toList()..sort();
    return list;
  }

  /// Επιστρέφει ώρα από "HH:mm" ή null.
  static ({int hour, int minute})? parseTime(String raw) {
    final t = raw.trim();
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return (hour: h, minute: min);
  }

  static bool hasValidTimeString(String? raw) =>
      raw != null && parseTime(raw) != null;

  static bool isScheduledWeekday(DateTime now, List<int> weekdays) =>
      weekdays.contains(now.weekday);

  /// True αν η τρέχουσα τοπική ώρα έχει φτάσει ή περάσει την [time] ("HH:mm") την ίδια ημέρα.
  static bool hasReachedTimeToday(DateTime now, String time) {
    final p = parseTime(time);
    if (p == null) return false;
    final slot =
        DateTime(now.year, now.month, now.day, p.hour, p.minute);
    return !now.isBefore(slot);
  }

  /// Τελευταία χρονική στιγμή προγράμματος που έχει **ήδη περάσει** (strictly <= now).
  static DateTime? lastPassedScheduleInstant(
    DateTime now,
    List<int> weekdays,
    String time,
  ) {
    final p = parseTime(time);
    if (p == null || weekdays.isEmpty) return null;

    final todaySlot =
        DateTime(now.year, now.month, now.day, p.hour, p.minute);
    if (weekdays.contains(now.weekday) && !todaySlot.isAfter(now)) {
      return todaySlot;
    }

    for (var d = 1; d <= 14; d++) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: d));
      final slot = DateTime(day.year, day.month, day.day, p.hour, p.minute);
      if (weekdays.contains(day.weekday) && !slot.isAfter(now)) {
        return slot;
      }
    }
    return null;
  }

  /// Ίδια τοπική ημερομηνία (χωρίς ώρα).
  static bool isSameLocalDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
