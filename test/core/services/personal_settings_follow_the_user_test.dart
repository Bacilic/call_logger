// Οι ρυθμίσεις που δηλώνονται προσωπικές ακολουθούν πράγματι τον χρήστη.
//
// Καθεμιά τους γραφόταν κάποτε κατευθείαν στην παλιά, κοινή θέση παρότι το
// κλειδί ήταν δηλωμένο προσωπικό — οπότε ο ένας πατούσε τη ρύθμιση του άλλου,
// σιωπηλά. Τα τεστ εδώ ελέγχουν το αποτέλεσμα όπως το ζει ο χρήστης: αλλάζω
// χρήστη, βλέπω τα δικά μου.
//
//   flutter test test/core/services/personal_settings_follow_the_user_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/old_database/lamp_settings_store.dart';
import 'package:call_logger/core/database/operator_settings_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/profile_settings.dart';
import 'package:call_logger/core/services/scoped_settings.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../test_setup.dart';

Operator _operator(int id) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  createdAt: DateTime(2026, 9, 17),
);

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CurrentOperator.reset();
    db = await DatabaseHelper.instance.database;
    await db.delete('app_settings');
    await db.delete(OperatorSettingsRepository.tableName);
    SettingsService.registerAppSettingsProvider(
      (key) => SettingsRepository(db).getSetting(key),
      (key, value) => SettingsRepository(db).saveSetting(key, value),
      (key, change) => SettingsRepository(db).updateSetting(key, change),
    );
  });

  tearDown(CurrentOperator.reset);

  test(
    'η ειδοποίηση ενημέρωσης ακολουθεί τον χρήστη, όχι το μηχάνημα',
    () async {
      final settings = SettingsService();

      CurrentOperator.activate(_operator(1));
      await settings.catalogs.setShowUpdateOnStartup(false);

      CurrentOperator.activate(_operator(2));
      expect(
        await settings.catalogs.getShowUpdateOnStartup(),
        isTrue,
        reason: 'Ο δεύτερος δεν την έκλεισε — βλέπει την προεπιλογή.',
      );

      CurrentOperator.activate(_operator(1));
      expect(
        await settings.catalogs.getShowUpdateOnStartup(),
        isFalse,
        reason: 'Η επιλογή του πρώτου τον ακολουθεί.',
      );
    },
  );

  test('το όριο αποτελεσμάτων της Λάμπας είναι δικό του καθενός', () async {
    final store = LampSettingsStore();

    CurrentOperator.activate(_operator(1));
    await store.setMaxSearchResults(250);

    CurrentOperator.activate(_operator(2));
    expect(
      await store.getMaxSearchResults(),
      LampSettingsStore.defaultMaxSearchResults,
      reason: 'Ο δεύτερος ξεκινά από την προεπιλογή.',
    );

    CurrentOperator.activate(_operator(1));
    expect(await store.getMaxSearchResults(), 250);
  });

  test('τα όρια του ορίου αποτελεσμάτων ισχύουν στην εγγραφή', () async {
    final store = LampSettingsStore();
    CurrentOperator.activate(_operator(1));

    await store.setMaxSearchResults(999999);

    expect(
      await ScopedSettings.getInt(ProfileSettingKeys.lampMaxSearchResults),
      LampSettingsStore.maxMaxSearchResults,
      reason:
          'Τιμή εκτός ορίων δεν αποθηκεύεται για να περικοπεί σιωπηλά σε κάθε '
          'ανάγνωση — κόβεται πριν γραφτεί.',
    );
  });

  test('το πλάτος της λίστας πινάκων είναι δικό του καθενός', () async {
    final store = LampSettingsStore();

    CurrentOperator.activate(_operator(1));
    await store.setTablesPaneWidthPx(320);

    CurrentOperator.activate(_operator(2));
    expect(
      await store.getTablesPaneWidthPx(),
      isNull,
      reason:
          'Ο δεύτερος δεν έχει δικό του πλάτος — η οθόνη βάζει το δικό της.',
    );

    CurrentOperator.activate(_operator(1));
    expect(await store.getTablesPaneWidthPx(), 320);
  });

  test('η μεγέθυνση προεπισκόπησης είναι δική του καθενός', () async {
    const zoom = ProfileSettingKeys.databaseBrowserPreviewZoomByTable;

    CurrentOperator.activate(_operator(1));
    await ScopedSettings.setString(zoom, '{"calls":1.5}');

    CurrentOperator.activate(_operator(2));
    expect(
      await ScopedSettings.getString(zoom),
      isNull,
      reason: 'Ο δεύτερος δεν όρισε ζουμ — διαβάζει στο 100%.',
    );

    CurrentOperator.activate(_operator(1));
    expect(await ScopedSettings.getString(zoom), '{"calls":1.5}');
  });

  test('χωρίς συνδεδεμένο χρήστη, όλα δουλεύουν όπως πριν', () async {
    final settings = SettingsService();
    final store = LampSettingsStore();

    await settings.catalogs.setShowUpdateOnStartup(false);
    await store.setMaxSearchResults(250);

    expect(await settings.catalogs.getShowUpdateOnStartup(), isFalse);
    expect(await store.getMaxSearchResults(), 250);
  });
}
