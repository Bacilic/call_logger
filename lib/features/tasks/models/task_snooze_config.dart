import 'package:flutter/material.dart';

/// Ρυθμίσεις αναβολών και εργάσιμων ωρών (αποθήκευση σε `app_settings`).
class TaskSnoozeConfig {
  const TaskSnoozeConfig({
    required this.dayEndTime,
    required this.nextBusinessHour,
    required this.skipWeekends,
    required this.defaultSnoozeOption,
    required this.maxSnoozeDays,
  });

  /// Κλειδί πίνακα `app_settings` για JSON ρυθμίσεων.
  static const String appSettingsKey = 'task_snooze_config';

  static const String kOneHour = 'one_hour';
  static const String kDayEnd = 'day_end';
  static const String kNextBusiness = 'next_business';

  /// Όρισμα `option` στο [TaskService.calculateNextDueDate]: χρήση [defaultSnoozeOption].
  static const String kOptionDefault = 'default';

  final TimeOfDay dayEndTime;
  final TimeOfDay nextBusinessHour;
  final bool skipWeekends;

  /// Μία από: [kOneHour], [kDayEnd], [kNextBusiness].
  final String defaultSnoozeOption;
  final int maxSnoozeDays;

  factory TaskSnoozeConfig.defaultConfig() {
    return TaskSnoozeConfig(
      dayEndTime: const TimeOfDay(hour: 13, minute: 0),
      nextBusinessHour: const TimeOfDay(hour: 8, minute: 0),
      skipWeekends: true,
      defaultSnoozeOption: kOneHour,
      maxSnoozeDays: 365,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dayEndTime': _timeToMap(dayEndTime),
      'nextBusinessHour': _timeToMap(nextBusinessHour),
      'skipWeekends': skipWeekends,
      'defaultSnoozeOption': defaultSnoozeOption,
      'maxSnoozeDays': maxSnoozeDays,
    };
  }

  factory TaskSnoozeConfig.fromMap(Map<String, dynamic> map) {
    final option = map['defaultSnoozeOption'] as String? ?? kOneHour;
    final validOption = _normalizeOption(option);
    return TaskSnoozeConfig(
      dayEndTime: _timeFromMap(map['dayEndTime']) ??
          const TimeOfDay(hour: 13, minute: 0),
      nextBusinessHour: _timeFromMap(map['nextBusinessHour']) ??
          const TimeOfDay(hour: 8, minute: 0),
      skipWeekends: map['skipWeekends'] is bool
          ? map['skipWeekends'] as bool
          : true,
      defaultSnoozeOption: validOption,
      maxSnoozeDays: _clampMaxDays(_readInt(map['maxSnoozeDays'], 365)),
    );
  }

  TaskSnoozeConfig copyWith({
    TimeOfDay? dayEndTime,
    TimeOfDay? nextBusinessHour,
    bool? skipWeekends,
    String? defaultSnoozeOption,
    int? maxSnoozeDays,
  }) {
    return TaskSnoozeConfig(
      dayEndTime: dayEndTime ?? this.dayEndTime,
      nextBusinessHour: nextBusinessHour ?? this.nextBusinessHour,
      skipWeekends: skipWeekends ?? this.skipWeekends,
      defaultSnoozeOption: defaultSnoozeOption != null
          ? _normalizeOption(defaultSnoozeOption)
          : this.defaultSnoozeOption,
      maxSnoozeDays: maxSnoozeDays != null
          ? _clampMaxDays(maxSnoozeDays)
          : this.maxSnoozeDays,
    );
  }

  static Map<String, int> _timeToMap(TimeOfDay t) {
    return {'hour': t.hour, 'minute': t.minute};
  }

  static TimeOfDay? _timeFromMap(dynamic v) {
    if (v is! Map) return null;
    final h = v['hour'];
    final m = v['minute'];
    final hour = h is int ? h : (h is num ? h.toInt() : null);
    final minute = m is int ? m : (m is num ? m.toInt() : null);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static int _readInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  static int _clampMaxDays(int v) => v.clamp(1, 365);

  static String _normalizeOption(String v) {
    switch (v) {
      case kOneHour:
      case kDayEnd:
      case kNextBusiness:
        return v;
      default:
        return kOneHour;
    }
  }

  /// Για επιλογή αναβολής από UI (επιτρέπει και άγνωστα strings → [kOneHour]).
  static String normalizeSnoozeOption(String v) => _normalizeOption(v);
}
