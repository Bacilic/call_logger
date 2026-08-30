// Οι έξι ρυθμίσεις εκκρεμοτήτων ζουν σε ΕΝΑ κλειδί. Δύο διαχειριστές με τον
// διάλογο ανοιχτό άλλαζαν διαφορετικά πράγματα — και ο δεύτερος έγραφε ολόκληρο
// το δέμα από την εικόνα που είχε φορτώσει, σβήνοντας την αλλαγή του πρώτου.
//
//   flutter test test/features/tasks/task_settings_concurrent_write_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/features/tasks/models/task_settings_config.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('TaskSettingsConfig.applyChanges — μόνο ό,τι άγγιξε ο χρήστης', () {
    final baseline = TaskSettingsConfig.defaultConfig();

    test('πεδίο που δεν άλλαξε δεν αγγίζει την τρέχουσα τιμή', () {
      // Ο χρήστης άλλαξε μόνο τις μέρες αναβολής.
      final draft = baseline.copyWith(maxSnoozeDays: 30);
      // Στο μεταξύ ο συνάδελφος άλλαξε την ώρα τέλους ημέρας.
      final fresh = baseline.copyWith(
        dayEndTime: const TimeOfDay(hour: 15, minute: 30),
      );

      final result = TaskSettingsConfig.applyChanges(
        from: baseline,
        to: draft,
        onto: fresh,
      );

      expect(result.maxSnoozeDays, 30, reason: 'η δική μου αλλαγή');
      expect(
        result.dayEndTime,
        const TimeOfDay(hour: 15, minute: 30),
        reason: 'η αλλαγή του συναδέλφου δεν επιτρέπεται να επανέλθει',
      );
    });

    test('αλλαγή στο ΙΔΙΟ πεδίο κερδίζει — είναι ρητή πρόθεση', () {
      final draft = baseline.copyWith(skipWeekends: false);
      final fresh = baseline.copyWith(skipWeekends: true);

      final result = TaskSettingsConfig.applyChanges(
        from: baseline,
        to: draft,
        onto: fresh,
      );

      expect(result.skipWeekends, isFalse);
    });

    test('χωρίς καμία αλλαγή η τρέχουσα τιμή μένει ακέραιη', () {
      final fresh = baseline.copyWith(
        maxSnoozeDays: 10,
        autoCloseQuickAdds: false,
        defaultSnoozeOption: TaskSettingsConfig.kNextBusiness,
      );

      final result = TaskSettingsConfig.applyChanges(
        from: baseline,
        to: baseline,
        onto: fresh,
      );

      expect(result.maxSnoozeDays, 10);
      expect(result.autoCloseQuickAdds, isFalse);
      expect(result.defaultSnoozeOption, TaskSettingsConfig.kNextBusiness);
    });

    test('και τα έξι πεδία περνούν όταν όλα άλλαξαν', () {
      final draft = baseline.copyWith(
        dayEndTime: const TimeOfDay(hour: 16, minute: 0),
        nextBusinessHour: const TimeOfDay(hour: 9, minute: 15),
        skipWeekends: !baseline.skipWeekends,
        defaultSnoozeOption: TaskSettingsConfig.kDayEnd,
        maxSnoozeDays: 45,
        autoCloseQuickAdds: !baseline.autoCloseQuickAdds,
      );

      final result = TaskSettingsConfig.applyChanges(
        from: baseline,
        to: draft,
        onto: baseline,
      );

      expect(result.dayEndTime, const TimeOfDay(hour: 16, minute: 0));
      expect(result.nextBusinessHour, const TimeOfDay(hour: 9, minute: 15));
      expect(result.skipWeekends, !baseline.skipWeekends);
      expect(result.defaultSnoozeOption, TaskSettingsConfig.kDayEnd);
      expect(result.maxSnoozeDays, 45);
      expect(result.autoCloseQuickAdds, !baseline.autoCloseQuickAdds);
    });
  });

  group('Ρυθμίσεις εκκρεμοτήτων — δύο διαχειριστές στο ίδιο κλειδί', () {
    late Database db;
    late TasksRepository repository;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('task_settings_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/tasks.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('app_settings');
      repository = TasksRepository();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    test('οι αλλαγές δύο διαχειριστών επιβιώνουν και οι δύο', () async {
      // Και οι δύο άνοιξαν τον διάλογο με την ίδια εικόνα.
      final opened = await repository.getTaskSettingsConfig();

      // Ο πρώτος αλλάζει την ώρα «τέλος ημέρας» και σώζει.
      await repository.updateTaskSettingsConfig(
        (current) => TaskSettingsConfig.applyChanges(
          from: opened,
          to: opened.copyWith(dayEndTime: const TimeOfDay(hour: 15, minute: 0)),
          onto: current,
        ),
      );

      // Ο δεύτερος, χωρίς να ξέρει, αλλάζει τις μέγιστες μέρες αναβολής.
      await repository.updateTaskSettingsConfig(
        (current) => TaskSettingsConfig.applyChanges(
          from: opened,
          to: opened.copyWith(maxSnoozeDays: 30),
          onto: current,
        ),
      );

      final stored = await repository.getTaskSettingsConfig();
      expect(stored.maxSnoozeDays, 30, reason: 'η δική μου αλλαγή');
      expect(
        stored.dayEndTime,
        const TimeOfDay(hour: 15, minute: 0),
        reason: 'η ώρα του συναδέλφου δεν επιτρέπεται να επανέλθει',
      );
    });

    test('η αποθήκευση επιστρέφει ό,τι όντως γράφτηκε', () async {
      final opened = await repository.getTaskSettingsConfig();
      await repository.updateTaskSettingsConfig(
        (current) => current.copyWith(skipWeekends: false),
      );

      final saved = await repository.updateTaskSettingsConfig(
        (current) => TaskSettingsConfig.applyChanges(
          from: opened,
          to: opened.copyWith(maxSnoozeDays: 7),
          onto: current,
        ),
      );

      expect(saved.maxSnoozeDays, 7);
      expect(
        saved.skipWeekends,
        isFalse,
        reason: 'η οθόνη μου μαθαίνει την αλλαγή του άλλου από την επιστροφή',
      );
    });

    test(
      'παλιό κλειδί ρυθμίσεων δεν χάνεται στην πρώτη στοχευμένη εγγραφή',
      () async {
        // Εγκατάσταση που δεν έχει ακόμη το νέο κλειδί, μόνο το παλιό.
        await db.insert('app_settings', {
          'key': TaskSettingsConfig.legacyAppSettingsKey,
          'value':
              '{"dayEndTime":{"hour":17,"minute":45},'
              '"skipWeekends":false,"maxSnoozeDays":12}',
        });

        final opened = await repository.getTaskSettingsConfig();
        expect(
          opened.maxSnoozeDays,
          12,
          reason: 'η ανάγνωση βλέπει το παλιό κλειδί',
        );

        await repository.updateTaskSettingsConfig(
          (current) => TaskSettingsConfig.applyChanges(
            from: opened,
            to: opened.copyWith(autoCloseQuickAdds: false),
            onto: current,
          ),
        );

        final stored = await repository.getTaskSettingsConfig();
        expect(stored.autoCloseQuickAdds, isFalse, reason: 'η δική μου αλλαγή');
        expect(
          stored.dayEndTime,
          const TimeOfDay(hour: 17, minute: 45),
          reason:
              'οι παλιές ρυθμίσεις δεν σβήνονται από τη μετάβαση στο νέο κλειδί',
        );
        expect(stored.maxSnoozeDays, 12);
      },
    );
  });
}
