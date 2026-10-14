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

  /// Επιλογή «Μέσα στο ωράριο» (`kDayEnd`): αν η [base] την ίδια ημερολογιακή ημέρα
  /// βρίσκεται από [nextBusinessHour] έως [dayEndTime] (συμπεριλαμβανομένων), +1 ώρα·
  /// αλλιώς επόμενη εργάσιμη στην [nextBusinessHour]. Αν το ωράριο δεν είναι έγκυρο
  /// (λήξη πριν την έναρξη), εφαρμόζεται +1 ώρα.
  static DateTime _withinScheduleOrNextBusinessDue(
    TaskSettingsConfig config,
    DateTime base,
  ) {
    final dayStart = DateTime(base.year, base.month, base.day);
    final startToday = _atTimeOnDay(dayStart, config.nextBusinessHour);
    final endToday = _atTimeOnDay(dayStart, config.dayEndTime);
    if (!endToday.isAfter(startToday)) {
      return base.add(const Duration(hours: 1));
    }
    if (!base.isBefore(startToday) && !base.isAfter(endToday)) {
      return base.add(const Duration(hours: 1));
    }
    return _nextBusinessMorningDateTime(config, base);
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
