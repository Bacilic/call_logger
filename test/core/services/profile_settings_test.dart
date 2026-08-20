// Το θεμέλιο των προσωπικών ρυθμίσεων (Φάση 2): ο πίνακας operator_settings,
// η αποθήκη του, και η πύλη εμβέλειας με τους κανόνες της:
// χωρίς χρήστη = όπως χθες · κληρονομιά κοινής τιμής μόνο στον διαχειριστή ·
// κληρονομιά τοπικής τιμής σε όποιον πρωτοκαθίσει · ανεξαρτησία χρηστών.
//
//   flutter test test/core/services/profile_settings_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/core/database/operator_settings_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/profile_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

Operator _operator(int id, {bool isAdmin = false}) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  isAdmin: isAdmin,
  createdAt: DateTime(2026, 8, 20),
);

const _machineKey = ProfileSettingKey(
  'test_machine_scoped_key',
  legacySource: ProfileSettingLegacySource.machine,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUpAll(() {
    initSqfliteFfiForTests();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CurrentOperator.reset();
    db = await openDatabase(inMemoryDatabasePath);
    await db.execute(kCreateOperatorsTable);
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute(kCreateOperatorSettingsTable);
  });

  tearDown(() async {
    CurrentOperator.reset();
    await db.close();
  });

  group('Μετάπτωση v48', () {
    test('φτιάχνει τον πίνακα operator_settings σε βάση v47', () async {
      final upgraded = await openDatabase(inMemoryDatabasePath);
      addTearDown(upgraded.close);
      // Βάση «σαν v47»: μόνο ό,τι χρειάζεται η αλυσίδα 47→48.
      await onDatabaseUpgradeSquashed(upgraded, 47, 48);

      final tables = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='operator_settings'",
      );
      expect(tables, hasLength(1));
    });

    test('είναι ακίνδυνη όταν ο πίνακας υπάρχει ήδη (idempotent)', () async {
      await onDatabaseUpgradeSquashed(db, 47, 48);
      await onDatabaseUpgradeSquashed(db, 47, 48);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='operator_settings'",
      );
      expect(tables, hasLength(1));
    });
  });

  group('OperatorSettingsRepository', () {
    test('κάθε χρήστης έχει τις δικές του τιμές, ανεξάρτητες', () async {
      final repo = OperatorSettingsRepository(db);
      await repo.setValue(1, 'k', 'του πρώτου');
      await repo.setValue(2, 'k', 'του δεύτερου');

      expect(await repo.getValue(1, 'k'), 'του πρώτου');
      expect(await repo.getValue(2, 'k'), 'του δεύτερου');

      await repo.deleteValue(1, 'k');
      expect(await repo.getValue(1, 'k'), isNull);
      expect(await repo.getValue(2, 'k'), 'του δεύτερου');
    });

    test('getAllForOperator επιστρέφει μόνο τα δικά του', () async {
      final repo = OperatorSettingsRepository(db);
      await repo.setValue(1, 'a', '1');
      await repo.setValue(1, 'b', '2');
      await repo.setValue(2, 'a', 'ξένο');

      expect(await repo.getAllForOperator(1), {'a': '1', 'b': '2'});
    });
  });

  group('Πύλη — χωρίς συνδεδεμένο χρήστη, όλα όπως χθες', () {
    test('read διαβάζει την παλιά κοινή θέση', () async {
      await SettingsRepository(
        db,
      ).saveSetting('database_backup_settings_v1', '{"παλιό":"δέμα"}');

      final gate = ProfileSettings(db, operator: null);
      expect(
        await gate.read(ProfileSettingKeys.databaseBackupSettings),
        '{"παλιό":"δέμα"}',
      );
    });

    test('write γράφει στην παλιά κοινή θέση', () async {
      final gate = ProfileSettings(db, operator: null);
      await gate.write(ProfileSettingKeys.databaseBackupSettings, '{"ν":1}');

      expect(
        await SettingsRepository(db).getSetting('database_backup_settings_v1'),
        '{"ν":1}',
      );
    });
  });

  group('Πύλη — κληρονομιά πρώτης ανάγνωσης', () {
    test('ο διαχειριστής κληρονομεί την κοινή τιμή, μία φορά', () async {
      await SettingsRepository(
        db,
      ).saveSetting('database_backup_settings_v1', '{"κοινό":"δέμα"}');

      final admin = _operator(1, isAdmin: true);
      final gate = ProfileSettings(db, operator: admin);
      expect(
        await gate.read(ProfileSettingKeys.databaseBackupSettings),
        '{"κοινό":"δέμα"}',
      );

      // Η κοινή τιμή αλλάζει μετά — το προφίλ ΔΕΝ την ακολουθεί πια.
      await SettingsRepository(
        db,
      ).saveSetting('database_backup_settings_v1', '{"άλλαξε":"μετά"}');
      expect(
        await gate.read(ProfileSettingKeys.databaseBackupSettings),
        '{"κοινό":"δέμα"}',
      );
    });

    test('ο απλός χρήστης ΔΕΝ κληρονομεί την κοινή τιμή', () async {
      await SettingsRepository(
        db,
      ).saveSetting('database_backup_settings_v1', '{"κοινό":"δέμα"}');

      final gate = ProfileSettings(db, operator: _operator(2));
      expect(
        await gate.read(ProfileSettingKeys.databaseBackupSettings),
        isNull,
      );
    });

    test('τοπική τιμή μηχανήματος κληρονομείται από οποιονδήποτε', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'test_machine_scoped_key': 'τοπική εμπειρία',
      });

      final gate = ProfileSettings(db, operator: _operator(2));
      expect(await gate.read(_machineKey), 'τοπική εμπειρία');

      // Κληρονομήθηκε στο προφίλ: η τοπική αλλαγή δεν το αγγίζει πια.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'test_machine_scoped_key': 'άλλαξε τοπικά',
      });
      expect(await gate.read(_machineKey), 'τοπική εμπειρία');
    });
  });

  group('Πύλη — με συνδεδεμένο χρήστη', () {
    test('write πάει στο προφίλ και δεν αγγίζει τα κοινά', () async {
      await SettingsRepository(
        db,
      ).saveSetting('database_backup_settings_v1', '{"κοινό":"δέμα"}');

      final gate = ProfileSettings(db, operator: _operator(3));
      await gate.write(
        ProfileSettingKeys.databaseBackupSettings,
        '{"δικό":"μου"}',
      );

      expect(
        await gate.read(ProfileSettingKeys.databaseBackupSettings),
        '{"δικό":"μου"}',
      );
      expect(
        await SettingsRepository(db).getSetting('database_backup_settings_v1'),
        '{"κοινό":"δέμα"}',
      );
    });

    test('δύο χρήστες δεν βλέπουν ο ένας τις τιμές του άλλου', () async {
      final first = ProfileSettings(db, operator: _operator(1));
      final second = ProfileSettings(db, operator: _operator(2));

      await first.write(ProfileSettingKeys.databaseBackupSettings, '{"α":1}');
      await second.write(ProfileSettingKeys.databaseBackupSettings, '{"β":2}');

      expect(
        await first.read(ProfileSettingKeys.databaseBackupSettings),
        '{"α":1}',
      );
      expect(
        await second.read(ProfileSettingKeys.databaseBackupSettings),
        '{"β":2}',
      );
    });

    test('χωρίς ρητό όρισμα, η πύλη μιλά για τον ενεργό χρήστη', () async {
      CurrentOperator.activate(_operator(5));
      final gate = ProfileSettings(db);
      await gate.write(ProfileSettingKeys.databaseBackupSettings, '{"ε":5}');

      expect(
        await OperatorSettingsRepository(
          db,
        ).getValue(5, 'database_backup_settings_v1'),
        '{"ε":5}',
      );
    });
  });
}
