// Tests: το κλειδί φτάνει στη βάση σφραγισμένο και γυρίζει πίσω αναγνώσιμο.
//
// Δεν αρκεί να δουλεύει το σφράγισμα μόνο του: η υπόσχεση είναι ότι κανένα
// σημείο του κώδικα δεν χρειάζεται να το ξέρει — γράφεις μέσω των ρυθμίσεων
// και η βάση κρατά σφραγισμένη τιμή.
//
//   flutter test test/core/database/settings_secret_sealing_roundtrip_test.dart

import 'package:call_logger/core/database/operator_settings_repository.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/database/settings_secret_sealing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _kApiKey = '00000000-dead-beef-cafe-000000000000';
const _kOperatorKey = 'gemini_api_key_override';

Future<String?> _rawSetting(Database db, String key) async {
  final rows = await db.query(
    'app_settings',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: [key],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first['value'] as String?;
}

Future<String?> _rawOperatorSetting(Database db, int operatorId) async {
  final rows = await db.query(
    OperatorSettingsRepository.tableName,
    columns: ['value'],
    where: 'operator_id = ? AND key = ?',
    whereArgs: [operatorId, _kOperatorKey],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first['value'] as String?;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
    );
    await db.execute(
      'CREATE TABLE ${OperatorSettingsRepository.tableName} ('
      'operator_id INTEGER, key TEXT, value TEXT, '
      'PRIMARY KEY (operator_id, key))',
    );
  });

  tearDown(() async => db.close());

  group('κοινές ρυθμίσεις', () {
    test('το κλειδί γράφεται σφραγισμένο και διαβάζεται αναγνώσιμο', () async {
      final repo = SettingsRepository(db);
      await repo.saveSetting(kLansweeperApiKeySettingKey, _kApiKey);

      final raw = await _rawSetting(db, kLansweeperApiKeySettingKey);
      expect(raw, isNotNull);
      expect(
        raw!.contains(_kApiKey),
        isFalse,
        reason: 'το κλειδί φαίνεται αυτούσιο σε όποιον ανοίξει τη βάση',
      );
      expect(isSealedSettingValue(raw), isTrue);

      expect(await repo.getSetting(kLansweeperApiKeySettingKey), _kApiKey);
    });

    test('ρύθμιση που δεν είναι μυστικό μένει αναγνώσιμη', () async {
      final repo = SettingsRepository(db);
      await repo.saveSetting(kLansweeperApiUrlSettingKey, 'http://server/x');

      expect(
        await _rawSetting(db, kLansweeperApiUrlSettingKey),
        'http://server/x',
      );
    });

    test(
      'παλιά ακάλυπτη τιμή διαβάζεται, και σφραγίζεται στην εκκίνηση',
      () async {
        final repo = SettingsRepository(db);
        // Γραμμένη πριν μπει το σφράγισμα — απευθείας στον πίνακα.
        await db.insert('app_settings', {
          'key': kGeminiApiKeySettingKey,
          'value': _kApiKey,
        });

        expect(await repo.getSetting(kGeminiApiKeySettingKey), _kApiKey);

        expect(await repo.sealUnsealedSecrets(), 1);
        final raw = await _rawSetting(db, kGeminiApiKeySettingKey);
        expect(isSealedSettingValue(raw!), isTrue);
        expect(raw.contains(_kApiKey), isFalse);
        expect(await repo.getSetting(kGeminiApiKeySettingKey), _kApiKey);
      },
    );

    test('η μετάπτωση είναι ακίνδυνο να ξανατρέξει', () async {
      final repo = SettingsRepository(db);
      await repo.saveSetting(kGeminiApiKeySettingKey, _kApiKey);

      expect(await repo.sealUnsealedSecrets(), 0);
      expect(await repo.getSetting(kGeminiApiKeySettingKey), _kApiKey);
    });

    test(
      'η ατομική αντικατάσταση απαγορεύεται για σφραγισμένη ρύθμιση',
      () async {
        final repo = SettingsRepository(db);
        expect(
          () => repo.compareAndSetSetting(
            kLansweeperApiKeySettingKey,
            null,
            _kApiKey,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('η μετάπτωση σχήματος', () {
    test('σφραγίζει και τα κοινά και τα προσωπικά κλειδιά', () async {
      await db.insert('app_settings', {
        'key': kLansweeperApiKeySettingKey,
        'value': _kApiKey,
      });
      await db.insert(OperatorSettingsRepository.tableName, {
        'operator_id': 4,
        'key': _kOperatorKey,
        'value': _kApiKey,
      });

      await migrateDatabaseToV67(db);

      expect(
        isSealedSettingValue(
          (await _rawSetting(db, kLansweeperApiKeySettingKey))!,
        ),
        isTrue,
      );
      expect(isSealedSettingValue((await _rawOperatorSetting(db, 4))!), isTrue);
    });

    test('η έκδοση σχήματος ανέβηκε — αλλιώς παλιός σταθμός στέλνει σφραγίδα '
        'αντί για κλειδί', () {
      expect(kDatabaseSchemaVersion, greaterThanOrEqualTo(67));
    });
  });

  group('προσωπικές ρυθμίσεις', () {
    test('το προσωπικό κλειδί ΤΝ γράφεται σφραγισμένο', () async {
      final repo = OperatorSettingsRepository(db);
      await repo.setValue(7, _kOperatorKey, _kApiKey);

      final raw = await _rawOperatorSetting(db, 7);
      expect(isSealedSettingValue(raw!), isTrue);
      expect(raw.contains(_kApiKey), isFalse);

      expect(await repo.getValue(7, _kOperatorKey), _kApiKey);
    });

    test('η μετάπτωση πιάνει κάθε χρήστη ξεχωριστά', () async {
      final repo = OperatorSettingsRepository(db);
      for (final operatorId in const [1, 2]) {
        await db.insert(OperatorSettingsRepository.tableName, {
          'operator_id': operatorId,
          'key': _kOperatorKey,
          'value': 'κλειδί-$operatorId',
        });
      }

      expect(await repo.sealUnsealedSecrets(), 2);
      expect(await repo.getValue(1, _kOperatorKey), 'κλειδί-1');
      expect(await repo.getValue(2, _kOperatorKey), 'κλειδί-2');
      expect(isSealedSettingValue((await _rawOperatorSetting(db, 2))!), isTrue);
    });
  });
}
