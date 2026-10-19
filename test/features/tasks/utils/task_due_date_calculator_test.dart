// Η προτεινόμενη προθεσμία εκκρεμότητας: «σε 1 ώρα», «μέσα στο ωράριο»,
// «επόμενη εργάσιμη», με ή χωρίς παράλειψη Σαββατοκύριακου.
//
//   flutter test test/features/tasks/utils/task_due_date_calculator_test.dart

import 'package:call_logger/features/tasks/models/task_settings_config.dart';
import 'package:call_logger/features/tasks/utils/task_due_date_calculator.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

/// Ωράριο 08:00–13:00, με παράλειψη Σαββατοκύριακου. Η 13/10/2026 είναι
/// Τρίτη, η 16/10 Παρασκευή, η 17/10 Σάββατο.
TaskSettingsConfig _config({
  String defaultOption = TaskSettingsConfig.kOneHour,
  bool skipWeekends = true,
  TimeOfDay start = const TimeOfDay(hour: 8, minute: 0),
  TimeOfDay end = const TimeOfDay(hour: 13, minute: 0),
}) => TaskSettingsConfig(
  dayEndTime: end,
  nextBusinessHour: start,
  skipWeekends: skipWeekends,
  defaultSnoozeOption: defaultOption,
  maxSnoozeDays: 365,
);

DateTime _due(
  TaskSettingsConfig config,
  DateTime from, {
  String option = TaskSettingsConfig.kOptionDefault,
}) => TaskDueDateCalculator.nextDueDate(config, option: option, fromDate: from);

void main() {
  group('σε 1 ώρα', () {
    test('η προεπιλογή των ρυθμίσεων εφαρμόζεται χωρίς ρητή επιλογή', () {
      expect(
        _due(_config(), DateTime(2026, 10, 13, 10)),
        DateTime(2026, 10, 13, 11),
      );
    });

    test('περνά τα μεσάνυχτα', () {
      expect(
        _due(
          _config(),
          DateTime(2026, 10, 13, 23, 30),
          option: TaskSettingsConfig.kOneHour,
        ),
        DateTime(2026, 10, 14, 0, 30),
      );
    });

    test('άγνωστη επιλογή καταλήγει σε 1 ώρα', () {
      expect(
        _due(
          _config(defaultOption: TaskSettingsConfig.kNextBusiness),
          DateTime(2026, 10, 13, 10),
          option: 'xyz',
        ),
        DateTime(2026, 10, 13, 11),
      );
    });
  });

  group('μέσα στο ωράριο', () {
    DateTime dayEnd(DateTime from, {TaskSettingsConfig? config}) =>
        _due(config ?? _config(), from, option: TaskSettingsConfig.kDayEnd);

    test('μέσα στο ωράριο: +1 ώρα', () {
      expect(dayEnd(DateTime(2026, 10, 13, 10)), DateTime(2026, 10, 13, 11));
    });

    test('στην έναρξη του ωραρίου: +1 ώρα', () {
      expect(dayEnd(DateTime(2026, 10, 13, 8)), DateTime(2026, 10, 13, 9));
    });

    test('στη λήξη του ωραρίου: η ώρα περνά στην επόμενη εργάσιμη', () {
      expect(dayEnd(DateTime(2026, 10, 13, 13)), DateTime(2026, 10, 14, 9));
    });

    test('λίγο πριν τη λήξη: ό,τι περισσεύει συνεχίζει αύριο', () {
      expect(
        dayEnd(DateTime(2026, 10, 13, 12, 30)),
        DateTime(2026, 10, 14, 8, 30),
      );
    });

    test('μετά το ωράριο: επόμενη εργάσιμη, έναρξη +1 ώρα', () {
      expect(dayEnd(DateTime(2026, 10, 13, 15)), DateTime(2026, 10, 14, 9));
    });

    test('πριν το ωράριο: σήμερα, έναρξη +1 ώρα', () {
      expect(dayEnd(DateTime(2026, 10, 13, 7)), DateTime(2026, 10, 13, 9));
    });

    test('Παρασκευή, τελευταία μισή ώρα: Δευτέρα πρωί', () {
      expect(
        dayEnd(DateTime(2026, 10, 16, 12, 30)),
        DateTime(2026, 10, 19, 8, 30),
      );
    });

    test('το Σαββατοκύριακο μένει πάντα εκτός, και χωρίς παράλειψη', () {
      expect(
        dayEnd(
          DateTime(2026, 10, 17, 10),
          config: _config(skipWeekends: false),
        ),
        DateTime(2026, 10, 19, 9),
      );
    });

    test('ωράριο που λήγει πριν αρχίσει: +1 ώρα', () {
      expect(
        dayEnd(
          DateTime(2026, 10, 13, 15),
          config: _config(end: const TimeOfDay(hour: 7, minute: 0)),
        ),
        DateTime(2026, 10, 13, 16),
      );
    });

    test('ως προεπιλογή των ρυθμίσεων', () {
      expect(
        _due(
          _config(defaultOption: TaskSettingsConfig.kDayEnd),
          DateTime(2026, 10, 13, 15),
        ),
        DateTime(2026, 10, 14, 9),
      );
    });
  });

  group('επόμενη εργάσιμη', () {
    test('Παρασκευή: Δευτέρα, με παράλειψη Σαββατοκύριακου', () {
      expect(
        _due(
          _config(),
          DateTime(2026, 10, 16, 10),
          option: TaskSettingsConfig.kNextBusiness,
        ),
        DateTime(2026, 10, 19, 8),
      );
    });

    test('Παρασκευή: Σάββατο, χωρίς παράλειψη Σαββατοκύριακου', () {
      expect(
        _due(
          _config(skipWeekends: false),
          DateTime(2026, 10, 16, 10),
          option: TaskSettingsConfig.kNextBusiness,
        ),
        DateTime(2026, 10, 17, 8),
      );
    });

    test('Σάββατο: Δευτέρα', () {
      expect(
        _due(
          _config(),
          DateTime(2026, 10, 17, 10),
          option: TaskSettingsConfig.kNextBusiness,
        ),
        DateTime(2026, 10, 19, 8),
      );
    });

    test('ακολουθεί την ώρα έναρξης των ρυθμίσεων', () {
      expect(
        _due(
          _config(start: const TimeOfDay(hour: 9, minute: 30)),
          DateTime(2026, 10, 13, 10),
          option: TaskSettingsConfig.kNextBusiness,
        ),
        DateTime(2026, 10, 14, 9, 30),
      );
    });

    test('κενή επιλογή σημαίνει την προεπιλογή των ρυθμίσεων', () {
      expect(
        _due(
          _config(defaultOption: TaskSettingsConfig.kNextBusiness),
          DateTime(2026, 10, 13, 10),
          option: '',
        ),
        DateTime(2026, 10, 14, 8),
      );
    });
  });
}
