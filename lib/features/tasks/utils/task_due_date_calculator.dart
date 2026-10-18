import 'package:flutter/material.dart' show TimeOfDay;

import '../models/task_settings_config.dart';

/// Η προτεινόμενη προθεσμία μιας εκκρεμότητας, από τις ρυθμίσεις ωραρίου.
///
/// Καθαρός υπολογισμός ημερολογίου: δεν διαβάζει τίποτα από τη βάση, ούτε
/// το «τώρα» όταν του δοθεί αφετηρία.
abstract final class TaskDueDateCalculator {
  /// Επόμενη προτεινόμενη ημερομηνία/ώρα λήξης βάσει ρυθμίσεων.
  ///
  /// [option]: `TaskSettingsConfig.kOptionDefault` → χρήση [TaskSettingsConfig.defaultSnoozeOption],
  /// αλλιώς `one_hour` / `day_end` («Μέσα στο ωράριο») / `next_business`.
  static DateTime nextDueDate(
    TaskSettingsConfig config, {
    String option = TaskSettingsConfig.kOptionDefault,
    DateTime? fromDate,
  }) {
    final base = fromDate ?? DateTime.now();
    final resolved =
        (option == TaskSettingsConfig.kOptionDefault || option.isEmpty)
        ? config.defaultSnoozeOption
        : TaskSettingsConfig.normalizeSnoozeOption(option);

    return switch (resolved) {
      TaskSettingsConfig.kOneHour => base.add(const Duration(hours: 1)),
      TaskSettingsConfig.kDayEnd => _withinScheduleOrNextBusinessDue(
        config,
        base,
      ),
      TaskSettingsConfig.kNextBusiness => _nextBusinessMorningDateTime(
        config,
        base,
      ),
      _ => base.add(const Duration(hours: 1)),
    };
  }

  static DateTime _atTimeOnDay(DateTime dayStart, TimeOfDay t) {
    return DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      t.hour,
      t.minute,
    );
  }

  /// Επιλογή «Μέσα στο ωράριο» (`kDayEnd`): **μία ώρα εργασίας**, μετρημένη
  /// μόνο μέσα στο ωράριο (απόφαση Διευθυντή 17/10/2026).
  /// - Μέσα στο ωράριο: +1 ώρα· ό,τι περισσεύει μετά τη λήξη συνεχίζει από
  ///   την έναρξη της επόμενης εργάσιμης (12:30 → αύριο 08:30).
  /// - Πριν ανοίξει, σε εργάσιμη: σήμερα, έναρξη +1 ώρα.
  /// - Στη λήξη ή μετά, και Σάββατο/Κυριακή: επόμενη εργάσιμη, έναρξη +1 ώρα.
  /// - Το Σαββατοκύριακο μένει **πάντα** εκτός, ανεξάρτητα από τη ρύθμιση
  ///   παράλειψης — αυτή αφορά μόνο την «Επόμενη εργάσιμη».
  ///
  /// Αν το ωράριο δεν είναι έγκυρο (λήξη πριν την έναρξη), +1 ώρα.
  static DateTime _withinScheduleOrNextBusinessDue(
    TaskSettingsConfig config,
    DateTime base,
  ) {
    final today = DateTime(base.year, base.month, base.day);
    final startToday = _atTimeOnDay(today, config.nextBusinessHour);
    final endToday = _atTimeOnDay(today, config.dayEndTime);
    if (!endToday.isAfter(startToday)) {
      return base.add(const Duration(hours: 1));
    }

    var day = today;
    var from = base;
    if (_isWeekend(day) || !base.isBefore(endToday)) {
      day = _nextWeekday(day);
      from = _atTimeOnDay(day, config.nextBusinessHour);
    } else if (base.isBefore(startToday)) {
      from = startToday;
    }

    var remaining = const Duration(hours: 1);
    while (true) {
      final end = _atTimeOnDay(day, config.dayEndTime);
      final available = end.difference(from);
      if (remaining <= available) return from.add(remaining);
      remaining -= available;
      day = _nextWeekday(day);
      from = _atTimeOnDay(day, config.nextBusinessHour);
    }
  }

  static bool _isWeekend(DateTime day) =>
      day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

  /// Η επόμενη ημέρα Δευτέρα–Παρασκευή μετά την [day].
  static DateTime _nextWeekday(DateTime day) {
    var next = DateTime(day.year, day.month, day.day + 1);
    while (_isWeekend(next)) {
      next = DateTime(next.year, next.month, next.day + 1);
    }
    return next;
  }

  /// Επόμενη ημέρα (ημερολογιακά μετά την ημέρα του [base]) στην [nextBusinessHour], με παράλειψη Σ/Κ αν [skipWeekends].
  static DateTime _nextBusinessMorningDateTime(
    TaskSettingsConfig config,
    DateTime base,
  ) {
    var day = DateTime(base.year, base.month, base.day);
    day = day.add(const Duration(days: 1));
    var candidate = _atTimeOnDay(day, config.nextBusinessHour);
    if (config.skipWeekends) {
      while (candidate.weekday == DateTime.saturday ||
          candidate.weekday == DateTime.sunday) {
        day = day.add(const Duration(days: 1));
        candidate = _atTimeOnDay(day, config.nextBusinessHour);
      }
    }
    return candidate;
  }
}
