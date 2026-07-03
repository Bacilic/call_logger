import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import '../utils/lexicon_word_metrics.dart';
import '../utils/search_text_normalizer.dart';
import 'database_init_result.dart';
import 'database_v1_schema.dart';
import 'dictionary_repository.dart';

/// Squashed schema version (ίδιο με [databaseSchemaVersionV1]).
const int kDatabaseSchemaVersion = databaseSchemaVersionV1;

/// Επαληθεύει ότι υπάρχει ο πίνακας `calls`. Αλλιώς ρίχνει [DatabaseInitException].
Future<void> validateDatabaseSchema(Database db, String dbPath) async {
  final r = await db.rawQuery('PRAGMA table_info(calls)');
  if (r.isEmpty) {
    throw DatabaseInitException(
      DatabaseInitResult.corruptedOrInvalid(
        dbPath,
        'Λείπει ο πίνακας calls· το αρχείο δεν φαίνεται έγκυρη βάση.',
      ),
    );
  }
}

/// Δημιουργία σχήματος v1 (squashed): όλοι οι πίνακες σε μία δημιουργία.
Future<void> onDatabaseCreate(Database db, int version) async {
  await applyDatabaseV1Schema(db);
}

/// Μήνυμα αναντιστοιχίας user_version (αρχείο) έναντι έκδοσης σχήματος εφαρμογής.
String schemaVersionMismatchUserMessage(
  Database db,
  int fileUserVersion,
  int appSchemaVersion,
) {
  final fileName = p.basename(db.path);
  return 'Το αρχείο της βάσης σας $fileName είναι στην έκδοση '
      '$fileUserVersion. Η εφαρμογή τρέχει την έκδοση '
      '$appSchemaVersion.\n\n'
      'Μπορείτε να:\n'
      '• Μετασχηματίσετε την βάση σας στη σωστή έκδοση με κάποιο script.\n'
      '• Να εντοπίσετε το σωστό αρχείο βάσης (μέσα από τις ρυθμίσεις).\n'
      '• Να δημιουργήσετε μια νέα βάση χωρίς δεδομένα (μέσα από τις ρυθμίσεις).';
}

/// Αναβάθμιση squashed σχήματος (π.χ. v1 → v2: στήλες `equipment.department_id`, `location`).
Future<void> onDatabaseUpgradeSquashed(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion >= newVersion) return;
  if (oldVersion == 0) return;
  // Sequential, idempotent migrations για άλματα εκδόσεων (π.χ. 2 -> 5).
  if (oldVersion < 2 && newVersion >= 2) {
    await migrateEquipmentDepartmentLocationColumns(db);
  }
  if (oldVersion < 3 && newVersion >= 3) {
    await migrateDepartmentPhonesTable(db);
  }
  if (oldVersion < 4 && newVersion >= 4) {
    await migrateDepartmentNameKey(db);
  }
  if (oldVersion < 5 && newVersion >= 5) {
    await migratePhonesDepartmentColumn(db);
  }
  if (oldVersion < 6 && newVersion >= 6) {
    await migrateUserDictionaryTable(db);
  }
  if (oldVersion < 7 && newVersion >= 7) {
    await migrateFullDictionaryTable(db);
  }
  if (oldVersion < 8 && newVersion >= 8) {
    await migrateUserDictionaryLanguageColumn(db);
  }
  if (oldVersion < 9 && newVersion >= 9) {
    await migrateLexiconWordMetricsColumns(db);
  }
  if (oldVersion < 10 && newVersion >= 10) {
    await migrateEquipmentRemoteParamsColumn(db);
  }
  if (oldVersion < 11 && newVersion >= 11) {
    await migrateDatabaseToV11(db);
  }
  if (oldVersion < 12 && newVersion >= 12) {
    await migrateDatabaseToV12(db);
  }
  if (oldVersion < 13 && newVersion >= 13) {
    await migrateDatabaseToV13(db);
  }
  if (oldVersion < 14 && newVersion >= 14) {
    await migrateDatabaseToV14(db);
  }
  if (oldVersion < 15 && newVersion >= 15) {
    await migrateDatabaseToV15(db);
  }
  if (oldVersion < 16 && newVersion >= 16) {
    await migrateDatabaseToV16(db);
  }
  if (oldVersion < 17 && newVersion >= 17) {
    await migrateDatabaseToV17(db);
  }
  if (oldVersion < 18 && newVersion >= 18) {
    await migrateDatabaseToV18(db);
  }
  if (oldVersion < 19 && newVersion >= 19) {
    await migrateDatabaseToV19(db);
  }
  if (oldVersion < 20 && newVersion >= 20) {
    await migrateDatabaseToV20(db);
  }
  if (oldVersion < 21 && newVersion >= 21) {
    await migrateDatabaseToV21(db);
  }
  if (oldVersion < 22 && newVersion >= 22) {
    await migrateDatabaseToV22(db);
  }
  if (oldVersion < 23 && newVersion >= 23) {
    await migrateDatabaseToV23(db);
  }
  if (oldVersion < 24 && newVersion >= 24) {
    await migrateDatabaseToV24(db);
  }
  if (oldVersion < 25 && newVersion >= 25) {
    await migrateDatabaseToV25(db);
  }
  if (oldVersion < 26 && newVersion >= 26) {
    await migrateDatabaseToV26(db);
  }
  if (oldVersion < 27 && newVersion >= 27) {
    await migrateDatabaseToV27(db);
  }
  if (oldVersion < 28 && newVersion >= 28) {
    await migrateDatabaseToV28(db);
  }
  if (oldVersion < 29 && newVersion >= 29) {
    await migrateDatabaseToV29(db);
  }
  if (oldVersion < 30 && newVersion >= 30) {
    await migrateDatabaseToV30(db);
  }
  if (oldVersion < 31 && newVersion >= 31) {
    await migrateDatabaseToV31(db);
  }
}

/// Αρχείο με νεότερο user_version (π.χ. 17) ενώ η εφαρμογή αναμένει squashed v1.
Future<void> onDatabaseDowngradeSquashed(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  throw DatabaseInitException(
    DatabaseInitResult(
      status: DatabaseStatus.applicationError,
      message: schemaVersionMismatchUserMessage(db, oldVersion, newVersion),
    ),
  );
}

/// Πίνακας προσωπικών λέξεων ορθογραφίας (Windows / custom lexicon).
Future<void> migrateUserDictionaryTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS user_dictionary (
        word TEXT PRIMARY KEY
      )
    ''');
}

/// v8: στήλη `language` + backfill με [DictionaryRepository.detectDictionaryLanguage].
Future<void> migrateUserDictionaryLanguageColumn(Database db) async {
  final info = await db.rawQuery(
    'PRAGMA table_info(${AppConfig.userDictionaryTable})',
  );
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('language')) {
    await db.execute(
      'ALTER TABLE ${AppConfig.userDictionaryTable} ADD COLUMN language TEXT',
    );
  }
  final rows = await db.query(
    AppConfig.userDictionaryTable,
    columns: ['word', 'language'],
  );
  final batch = db.batch();
  var pending = 0;
  for (final r in rows) {
    final w = (r['word'] as String?)?.trim() ?? '';
    if (w.isEmpty) continue;
    final next = DictionaryRepository.detectDictionaryLanguage(w);
    final cur = r['language'] as String? ?? '';
    if (cur == next) continue;
    batch.update(
      AppConfig.userDictionaryTable,
      {'language': next},
      where: 'word = ?',
      whereArgs: [w],
    );
    pending++;
  }
  if (pending > 0) await batch.commit(noResult: true);
}

/// v9: `letters_count`, `diacritic_mark_count` + backfill + ευρετήρια.
Future<void> migrateLexiconWordMetricsColumns(Database db) async {
  Future<void> ensureColumns(String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final names = info.map((r) => r['name'] as String).toSet();
    if (!names.contains('letters_count')) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN letters_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!names.contains('diacritic_mark_count')) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN diacritic_mark_count INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  await ensureColumns(AppConfig.fullDictionaryTable);
  await ensureColumns(AppConfig.userDictionaryTable);

  Future<void> backfillTable(String table, {required bool hasRowId}) async {
    final rows = await db.query(
      table,
      columns: hasRowId ? ['id', 'word'] : ['word'],
    );
    const chunk = 400;
    for (var i = 0; i < rows.length; i += chunk) {
      final end = (i + chunk > rows.length) ? rows.length : i + chunk;
      final slice = rows.sublist(i, end);
      final batch = db.batch();
      for (final r in slice) {
        final w = (r['word'] as String?) ?? '';
        final m = LexiconWordMetrics.compute(w);
        if (hasRowId) {
          final idRaw = r['id'];
          final id = idRaw is int ? idRaw : (idRaw as num).toInt();
          batch.update(
            table,
            {
              'letters_count': m.lettersCount,
              'diacritic_mark_count': m.diacriticMarkCount,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          batch.update(
            table,
            {
              'letters_count': m.lettersCount,
              'diacritic_mark_count': m.diacriticMarkCount,
            },
            where: 'word = ?',
            whereArgs: [w],
          );
        }
      }
      await batch.commit(noResult: true);
    }
  }

  await backfillTable(AppConfig.fullDictionaryTable, hasRowId: true);
  await backfillTable(AppConfig.userDictionaryTable, hasRowId: false);

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_letters_count ON ${AppConfig.fullDictionaryTable}(letters_count)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_diacritic_mark_count ON ${AppConfig.fullDictionaryTable}(diacritic_mark_count)',
  );
}

/// Πίνακας master λεξικού (v7).
Future<void> migrateFullDictionaryTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS full_dictionary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL UNIQUE,
        normalized_word TEXT NOT NULL,
        source TEXT NOT NULL,
        language TEXT NOT NULL,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_norm ON full_dictionary(normalized_word)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_full_dictionary_filters ON full_dictionary(language, source, category)',
  );
}

/// v10: στήλη `equipment.remote_params` για JSON παραμέτρων ανά εργαλείο.
Future<void> migrateEquipmentRemoteParamsColumn(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(equipment)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('remote_params')) {
    await db.execute('ALTER TABLE equipment ADD COLUMN remote_params TEXT');
  }
}

/// Προσθέτει στήλες τμήμα/τοποθεσία στον πίνακα `equipment` αν λείπουν (idempotent).
Future<void> migrateEquipmentDepartmentLocationColumns(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(equipment)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('department_id')) {
    await db.execute(
      'ALTER TABLE equipment ADD COLUMN department_id INTEGER',
    );
  }
  if (!names.contains('location')) {
    await db.execute('ALTER TABLE equipment ADD COLUMN location TEXT');
  }
}

/// Δημιουργεί πίνακα `department_phones` αν λείπει (idempotent).
Future<void> migrateDepartmentPhonesTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS department_phones (
        department_id INTEGER NOT NULL,
        phone_id INTEGER NOT NULL,
        PRIMARY KEY (department_id, phone_id)
      )
    ''');
}

const String _kDepartmentsNameKeyColumn = 'name_key';

/// Προσθέτει `departments.name_key` και το γεμίζει για υπάρχουσες εγγραφές.
Future<void> migrateDepartmentNameKey(Database db) async {
  const tableName = 'departments';
  final info = await db.rawQuery('PRAGMA table_info($tableName)');
  if (info.isEmpty) {
    throw Exception(
      'Μετάβαση σχήματος: δεν υπάρχει ο πίνακας `$tableName` (PRAGMA table_info '
      'επέστρεψε κενό). no such table: $tableName',
    );
  }
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains(_kDepartmentsNameKeyColumn)) {
    const stmt = 'ALTER TABLE departments ADD COLUMN name_key TEXT';
    try {
      await db.execute(stmt);
    } catch (e) {
      throw Exception(
        'Μετάβαση σχήματος απέτυχε: πίνακας `$tableName`, εντολή: `$stmt`. $e',
      );
    }
  }

  final rows = await db.query(
    'departments',
    columns: ['id', 'name', 'name_key'],
  );
  for (final r in rows) {
    final id = r['id'] as int?;
    if (id == null) continue;
    final existing = (r['name_key'] as String?)?.trim() ?? '';
    if (existing.isNotEmpty) continue;
    final name = (r['name'] as String?)?.trim() ?? '';
    final key = SearchTextNormalizer.normalizeForSearch(name);
    if (key.isEmpty) continue;
    await db.update(
      'departments',
      {_kDepartmentsNameKeyColumn: key},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_departments_name_key ON departments(name_key)',
  );
}

/// Προσθέτει `phones.department_id` για πολιτική shared-location.
Future<void> migratePhonesDepartmentColumn(Database db) async {
  final info = await db.rawQuery('PRAGMA table_info(phones)');
  final names = info.map((r) => r['name'] as String).toSet();
  if (!names.contains('department_id')) {
    await db.execute('ALTER TABLE phones ADD COLUMN department_id INTEGER');
  }
}
