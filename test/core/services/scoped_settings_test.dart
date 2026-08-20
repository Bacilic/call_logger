// Φάση 2 — Πακέτο Γ: το στρώμα που ξέρει σε ποια εμβέλεια ανήκει κάθε κλειδί.
//
// Το κρίσιμο συμβόλαιο: **χωρίς συνδεδεμένο χρήστη όλα δουλεύουν όπως χθες** —
// τα κοινά κλειδιά στη βάση (με τη γραφή `1`/`0` που είχαν πάντα), τα τοπικά
// στις ρυθμίσεις του υπολογιστή, τυπωμένα. Με χρήστη, η τιμή ζει στο προφίλ
// του και τον ακολουθεί.
//
//   flutter test test/core/services/scoped_settings_test.dart

import 'package:call_logger/core/database/database_helper.dart';
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

Operator _operator(int id, {bool isAdmin = false}) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  isAdmin: isAdmin,
  createdAt: DateTime(2026, 8, 20),
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
    // Ο καθιερωμένος πάροχος κοινών ρυθμίσεων, όπως τον στήνει η εφαρμογή
    // μετά το άνοιγμα της βάσης.
    SettingsService.registerAppSettingsProvider(
      (key) => SettingsRepository(db).getSetting(key),
      (key, value) => SettingsRepository(db).saveSetting(key, value),
    );
  });

  tearDown(CurrentOperator.reset);

  group('Κοινό κλειδί χωρίς συνδεδεμένο χρήστη — όπως χθες', () {
    test('η λογική τιμή γράφεται στη βάση ως «1»/«0»', () async {
      await ScopedSettings.setBool(
        ProfileSettingKeys.callsShowSecondaryRemoteActions,
        false,
      );

      expect(
        await SettingsRepository(
          db,
        ).getSetting('calls_show_secondary_remote_actions'),
        '0',
        reason:
            'Παλαιότερη έκδοση της εφαρμογής διαβάζει «1»/«0» — αλλαγή γραφής '
            'θα της έδινε τιμή που δεν αναγνωρίζει.',
      );
      expect(
        await ScopedSettings.getBool(
          ProfileSettingKeys.callsShowSecondaryRemoteActions,
        ),
        isFalse,
      );
    });

    test('διαβάζει σωστά και τις δύο ιστορικές γραφές', () async {
      final repo = SettingsRepository(db);
      await repo.saveSetting('calls_show_empty_remote_launchers', '1');
      expect(
        await ScopedSettings.getBool(
          ProfileSettingKeys.callsShowEmptyRemoteLaunchers,
        ),
        isTrue,
      );

      await repo.saveSetting('calls_show_empty_remote_launchers', 'false');
      expect(
        await ScopedSettings.getBool(
          ProfileSettingKeys.callsShowEmptyRemoteLaunchers,
        ),
        isFalse,
      );
    });
  });

  group('Τοπικό κλειδί χωρίς συνδεδεμένο χρήστη — όπως χθες', () {
    test('μένει στις ρυθμίσεις του υπολογιστή, τυπωμένο', () async {
      await ScopedSettings.setBool(ProfileSettingKeys.showActiveTimer, false);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('show_active_timer'),
        isFalse,
        reason:
            'Η τιμή δεν επιτρέπεται να αλλάξει τύπο κάτω από τα πόδια '
            'παλαιότερης έκδοσης.',
      );
      expect(
        await ScopedSettings.getBool(ProfileSettingKeys.showActiveTimer),
        isFalse,
      );
      expect(
        await SettingsRepository(db).getSetting('show_active_timer'),
        isNull,
        reason: 'Τοπικό κλειδί δεν έχει καμία δουλειά στη βάση.',
      );
    });
  });

  group('Με συνδεδεμένο χρήστη', () {
    test('η τιμή ζει στο προφίλ, τα κοινά μένουν ανέγγιχτα', () async {
      await SettingsRepository(
        db,
      ).saveSetting('lansweeper_agent_username', 'koinos');

      CurrentOperator.activate(_operator(1));
      await ScopedSettings.setString(
        ProfileSettingKeys.lansweeperAgentUsername,
        'dikos_mou',
      );

      expect(
        await ScopedSettings.getString(
          ProfileSettingKeys.lansweeperAgentUsername,
        ),
        'dikos_mou',
      );
      expect(
        await SettingsRepository(db).getSetting('lansweeper_agent_username'),
        'koinos',
      );
    });

    test('δύο χρήστες δεν βλέπουν ο ένας τις τιμές του άλλου', () async {
      CurrentOperator.activate(_operator(1));
      await ScopedSettings.setBool(ProfileSettingKeys.showLampNav, false);

      CurrentOperator.activate(_operator(2));
      await ScopedSettings.setBool(ProfileSettingKeys.showLampNav, true);

      CurrentOperator.activate(_operator(1));
      expect(
        await ScopedSettings.getBool(ProfileSettingKeys.showLampNav),
        isFalse,
      );
    });

    test(
      'κληρονομιά τοπικής τιμής: κανείς δεν χάνει τη σημερινή εμπειρία',
      () async {
        // Ο υπολογιστής έχει ήδη ρυθμισμένη προτίμηση, αποθηκευμένη ΤΥΠΩΜΕΝΑ.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'nav_rail_show_labels': false,
        });

        CurrentOperator.activate(_operator(5));
        expect(
          await ScopedSettings.getBool(ProfileSettingKeys.navRailShowLabels),
          isFalse,
          reason:
              'Μια αποθηκευμένη λογική τιμή δεν διαβάζεται ως κείμενο — '
              'η κληρονομιά πρέπει να τη μετατρέπει.',
        );
      },
    );

    test('κληρονομιά κοινής τιμής μόνο για τον διαχειριστή', () async {
      await SettingsRepository(
        db,
      ).saveSetting('gemini_prompt_template', 'το πρότυπο του διαχειριστή');

      CurrentOperator.activate(_operator(10, isAdmin: true));
      expect(
        await ScopedSettings.getString(ProfileSettingKeys.geminiPromptTemplate),
        'το πρότυπο του διαχειριστή',
      );

      CurrentOperator.activate(_operator(11));
      expect(
        await ScopedSettings.getString(ProfileSettingKeys.geminiPromptTemplate),
        isNull,
      );
    });

    test('ακέραιες και δεκαδικές τιμές κάνουν σωστό γύρο', () async {
      CurrentOperator.activate(_operator(7));
      await ScopedSettings.setInt(ProfileSettingKeys.lexiconPageSize, 250);
      await ScopedSettings.setDouble(
        ProfileSettingKeys.lampTablesLeftPaneWidth,
        320.5,
      );

      expect(
        await ScopedSettings.getInt(ProfileSettingKeys.lexiconPageSize),
        250,
      );
      expect(
        await ScopedSettings.getDouble(
          ProfileSettingKeys.lampTablesLeftPaneWidth,
        ),
        320.5,
      );
    });

    test('remove σβήνει τη δική μου τιμή, όχι την κοινή', () async {
      await SettingsRepository(
        db,
      ).saveSetting('catalog_continuous_scroll', 'κοινό');

      CurrentOperator.activate(_operator(8));
      await ScopedSettings.setString(
        ProfileSettingKeys.catalogContinuousScroll,
        'δικό μου',
      );
      await ScopedSettings.remove(ProfileSettingKeys.catalogContinuousScroll);

      expect(
        await SettingsRepository(db).getSetting('catalog_continuous_scroll'),
        'κοινό',
      );
    });
  });

  group('Ο κατάλογος κλειδιών', () {
    test('δεν έχει διπλά κλειδιά', () {
      final keys = ProfileSettingKeys.all.map((k) => k.key).toList();
      expect(
        keys.toSet(),
        hasLength(keys.length),
        reason: 'Δύο δηλώσεις για το ίδιο κλειδί θα διαφωνούσαν σιωπηλά.',
      );
    });

    test('το μέγεθος και η θέση του παραθύρου ΔΕΝ είναι προσωπικά', () {
      // Κλειδωμένη απόφαση Φάσης 0: οι συντεταγμένες εξαρτώνται από την οθόνη
      // του συγκεκριμένου υπολογιστή.
      final keys = ProfileSettingKeys.all.map((k) => k.key);
      for (final forbidden in const [
        'window_width_v1',
        'window_height_v1',
        'window_position_x_v1',
        'window_position_y_v1',
        'window_placement_mode_v1',
      ]) {
        expect(keys, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('κάθε προσωπικό κλειδί δηλώνει από πού κληρονομεί', () {
      for (final key in ProfileSettingKeys.all) {
        expect(
          key.legacySource,
          isNot(ProfileSettingLegacySource.none),
          reason:
              '${key.key}: χωρίς πηγή κληρονομιάς, ο χρήστης θα έχανε τη '
              'σημερινή του ρύθμιση στη μετάβαση.',
        );
      }
    });
  });
}
