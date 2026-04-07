import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';
import '../services/dictionary_service.dart';
import '../utils/lexicon_word_metrics.dart';

/// Πρόσβαση σε `user_dictionary` / `full_dictionary` και ενωμένα queries λεξικού.
class DictionaryRepository {
  DictionaryRepository(this.db);

  /// Άμεση πρόσβαση στη σύνδεση SQLite (π.χ. raw queries, χειροκίνητα transactions).
  final Database db;

  /// Heuristic γλώσσας λέξης για πίνακα λεξικού.
  static String detectDictionaryLanguage(String word) {
    final s = word.trim();
    if (s.isEmpty) return kLexiconLanguageMix;
    if (_reLexiconGreekOnly.hasMatch(s)) return 'el';
    if (_reLexiconLatinAsciiOnly.hasMatch(s)) return 'en';
    return kLexiconLanguageMix;
  }

  static final RegExp _reLexiconGreekOnly = RegExp(
    r'^['
    r'\u0391-\u03A9\u03B1-\u03C9'
    r'\u0386\u0388-\u038A\u038C\u038E-\u038F'
    r'\u0390\u03AA\u03AB\u03AC-\u03CE'
    r'\u03CA\u03CB'
    r'\u1F00-\u1FFC'
    r'\s'
    r']+$',
    unicode: true,
  );

  static final RegExp _reLexiconLatinAsciiOnly = RegExp(r'^[a-zA-Z\s]+$');

  static const String kLexiconSourceDraft = 'draft';
  static const String kLexiconPendingFilter = '__pending__';
  static const String kLexiconMixedScriptsFilter = '__mixed_scripts__';
  static const String kLexiconLanguageMix = 'mix';

  static String lexiconSourceUiLabel(String? src) {
    switch (src ?? '') {
      case kLexiconSourceDraft:
        return 'Πρόχειρο';
      case 'user':
        return 'Χρήστης';
      case 'imported':
      case 'system':
        return 'Εισαγωγή';
      default:
        final s = src ?? '';
        return s.isEmpty ? '—' : s;
    }
  }

  Future<void> insertUserWord(String word) async {
    final key = DictionaryService.canonicalLexiconKey(word);
    if (key.length < 2) return;
    final m = LexiconWordMetrics.compute(key);
    await db.insert(AppConfig.userDictionaryTable, {
      'word': key,
      'language': detectDictionaryLanguage(key),
      'letters_count': m.lettersCount,
      'diacritic_mark_count': m.diacriticMarkCount,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> addUserWord(String word) => insertUserWord(word);

  Future<List<String>> getUserWords() async {
    final rows = await db.query(
      AppConfig.userDictionaryTable,
      columns: ['word'],
      orderBy: 'word COLLATE NOCASE',
    );
    return rows
        .map((r) => (r['word'] as String?)?.trim() ?? '')
        .where((w) => w.isNotEmpty)
        .toList();
  }

  Future<void> deleteUserDictionaryWord(String normalizedKey) async {
    await db.delete(
      AppConfig.userDictionaryTable,
      where: 'word = ?',
      whereArgs: [normalizedKey],
    );
  }

  Future<void> updateUserDictionaryWordKey(String oldKey, String newKey) async {
    if (oldKey == newKey) return;
    await db.transaction((txn) async {
      await txn.delete(
        AppConfig.userDictionaryTable,
        where: 'word = ?',
        whereArgs: [newKey],
      );
      final m = LexiconWordMetrics.compute(newKey);
      await txn.update(
        AppConfig.userDictionaryTable,
        {
          'word': newKey,
          'language': detectDictionaryLanguage(newKey),
          'letters_count': m.lettersCount,
          'diacritic_mark_count': m.diacriticMarkCount,
        },
        where: 'word = ?',
        whereArgs: [oldKey],
      );
    });
  }

  Future<void> clearUserDictionary() async {
    await db.delete(AppConfig.userDictionaryTable);
  }

  Future<int> countFullDictionaryTotal() async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppConfig.fullDictionaryTable}',
    );
    if (r.isEmpty) return 0;
    return (r.first['c'] as int?) ?? 0;
  }

  Future<int> countFullDictionaryExactWord(String word) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppConfig.fullDictionaryTable} WHERE word = ?',
      [word],
    );
    if (r.isEmpty) return 0;
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> hardDeleteFullDictionaryById(int id) async {
    await db.delete(
      AppConfig.fullDictionaryTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearFullDictionary() async {
    await db.delete(AppConfig.fullDictionaryTable);
  }

  Future<void> batchInsertFullDictionaryRows(
    List<Map<String, dynamic>> rows, {
    int chunkSize = 800,
  }) async {
    if (rows.isEmpty) return;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final end = (i + chunkSize > rows.length) ? rows.length : i + chunkSize;
      final slice = rows.sublist(i, end);
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final row in slice) {
          final copy = Map<String, dynamic>.from(row);
          final w = (copy['word'] as String?)?.trim() ?? '';
          final m = LexiconWordMetrics.compute(w);
          copy['letters_count'] = m.lettersCount;
          copy['diacritic_mark_count'] = m.diacriticMarkCount;
          batch.insert(
            AppConfig.fullDictionaryTable,
            copy,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      });
    }
  }

  Future<void> upsertFullDictionaryCategory({
    required int id,
    required String category,
    String? newDisplayWord,
  }) async {
    final row = <String, dynamic>{'category': category};
    if (newDisplayWord != null && newDisplayWord.trim().isNotEmpty) {
      final w = newDisplayWord.trim();
      row['word'] = w;
      row['normalized_word'] = DictionaryService.canonicalLexiconKey(w);
      final m = LexiconWordMetrics.compute(w);
      row['letters_count'] = m.lettersCount;
      row['diacritic_mark_count'] = m.diacriticMarkCount;
      final dupRows = await db.rawQuery(
        'SELECT id, word FROM ${AppConfig.fullDictionaryTable} WHERE word = ? AND id != ? LIMIT 2',
        [w, id],
      );
      if (dupRows.isNotEmpty) {
        throw Exception(
          'Η λέξη "$w" υπάρχει ήδη στο λεξικό. Χρησιμοποίησε διαφορετική μορφή ή διέγραψε πρώτα την υπάρχουσα εγγραφή.',
        );
      }
    }
    await db.update(
      AppConfig.fullDictionaryTable,
      row,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsertFullFromUserDraft({
    required String normalizedKey,
    required String displayWord,
    required String category,
    required String language,
    String source = 'user',
  }) async {
    final w = displayWord.trim();
    final m = LexiconWordMetrics.compute(w);
    await db.insert(
      AppConfig.fullDictionaryTable,
      {
        'word': w,
        'normalized_word': normalizedKey,
        'source': source,
        'language': language,
        'category': category,
        'letters_count': m.lettersCount,
        'diacritic_mark_count': m.diacriticMarkCount,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> getDictionaryExportDisplayLinesOrdered() async {
    final fullRows = await db.query(
      AppConfig.fullDictionaryTable,
      columns: ['word', 'normalized_word'],
      orderBy: 'normalized_word COLLATE NOCASE',
    );
    final userRows = await db.query(
      AppConfig.userDictionaryTable,
      columns: ['word'],
      orderBy: 'word COLLATE NOCASE',
    );
    final byNorm = <String, String>{};
    for (final r in fullRows) {
      final nw = (r['normalized_word'] as String?)?.trim() ?? '';
      final w = (r['word'] as String?)?.trim() ?? '';
      if (nw.isEmpty || w.isEmpty) continue;
      byNorm[nw] = w;
    }
    for (final r in userRows) {
      final w = (r['word'] as String?)?.trim() ?? '';
      if (w.isEmpty || w.length < 2) continue;
      final canon = DictionaryService.canonicalLexiconKey(w);
      byNorm.putIfAbsent(canon, () => w);
    }
    final keys = byNorm.keys.toList()..sort((a, b) => a.compareTo(b));
    return keys.map((k) => byNorm[k]!).toList();
  }

  Future<void> mergeAllUserDictionaryIntoFullWithinTransaction(
    Transaction txn,
  ) async {
    final userRows = await txn.query(AppConfig.userDictionaryTable, columns: ['word']);
    for (final r in userRows) {
      final key = (r['word'] as String?)?.trim() ?? '';
      if (key.length < 2) continue;
      final norm = DictionaryService.canonicalLexiconKey(key);
      final lang = detectDictionaryLanguage(key);
      final m = LexiconWordMetrics.compute(key);
      await txn.insert(
        AppConfig.fullDictionaryTable,
        {
          'word': key,
          'normalized_word': norm,
          'source': 'user',
          'language': lang,
          'category': AppConfig.lexiconCategoryUnspecified,
          'letters_count': m.lettersCount,
          'diacritic_mark_count': m.diacriticMarkCount,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await txn.delete(AppConfig.userDictionaryTable);
  }

  /// Βολέ: ένα transaction merge user_dictionary → full_dictionary.
  Future<void> mergeUserToFullDictionary() async {
    await db.transaction((txn) async {
      await mergeAllUserDictionaryIntoFullWithinTransaction(txn);
    });
  }

  Future<int> countCombinedLexiconRows({
    String? language,
    String? source,
    String? category,
    String? normalizedSearch,
    bool pendingOnly = false,
    String? lettersCountOp,
    int? lettersCountValue,
    String? diacriticMarksFilter,
  }) async {
    final (sql, args) = _buildCombinedLexiconSql(
      language: language,
      source: source,
      category: category,
      normalizedSearch: normalizedSearch,
      pendingOnly: pendingOnly,
      lettersCountOp: lettersCountOp,
      lettersCountValue: lettersCountValue,
      diacriticMarksFilter: diacriticMarksFilter,
      limit: null,
      offset: null,
      countOnly: true,
    );
    final rows = await db.rawQuery(sql, args);
    if (rows.isEmpty) return 0;
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> queryCombinedLexiconPage({
    String? language,
    String? source,
    String? category,
    String? normalizedSearch,
    bool pendingOnly = false,
    String? lettersCountOp,
    int? lettersCountValue,
    String? diacriticMarksFilter,
    required int limit,
    required int offset,
  }) async {
    final (sql, args) = _buildCombinedLexiconSql(
      language: language,
      source: source,
      category: category,
      normalizedSearch: normalizedSearch,
      pendingOnly: pendingOnly,
      lettersCountOp: lettersCountOp,
      lettersCountValue: lettersCountValue,
      diacriticMarksFilter: diacriticMarksFilter,
      limit: limit,
      offset: offset,
      countOnly: false,
    );
    return db.rawQuery(sql, args);
  }

  (String, List<Object?>) _buildCombinedLexiconSql({
    String? language,
    String? source,
    String? category,
    String? normalizedSearch,
    required bool pendingOnly,
    String? lettersCountOp,
    int? lettersCountValue,
    String? diacriticMarksFilter,
    int? limit,
    int? offset,
    required bool countOnly,
  }) {
    final args = <Object?>[];
    final fullWhere = StringBuffer('1=1');
    if (normalizedSearch != null && normalizedSearch.trim().isNotEmpty) {
      fullWhere.write(' AND f.normalized_word LIKE ?');
      args.add('%${normalizedSearch.trim()}%');
    }

    final draftWhere = StringBuffer('1=1');
    if (normalizedSearch != null && normalizedSearch.trim().isNotEmpty) {
      draftWhere.write(' AND u.word LIKE ?');
      args.add('%${normalizedSearch.trim()}%');
    }

    var innerSelect = '''
WITH full_part AS (
  SELECT
    f.id AS entry_id,
    f.word AS display_word,
    f.normalized_word AS norm_key,
    f.source AS src,
    f.language AS lang,
    f.category AS cat,
    f.created_at AS created_ts,
    CASE WHEN EXISTS (SELECT 1 FROM ${AppConfig.userDictionaryTable} u WHERE u.word = f.normalized_word)
      THEN 1 ELSE 0 END AS pending_user,
    f.letters_count AS letters_count,
    f.diacritic_mark_count AS diacritic_mark_count
  FROM ${AppConfig.fullDictionaryTable} f
  WHERE $fullWhere
),
draft_part AS (
  SELECT
    CAST(NULL AS INTEGER) AS entry_id,
    u.word AS display_word,
    u.word AS norm_key,
    '$kLexiconSourceDraft' AS src,
    COALESCE(u.language, 'en') AS lang,
    '${AppConfig.lexiconCategoryUnspecified.replaceAll("'", "''")}' AS cat,
    CAST(NULL AS TEXT) AS created_ts,
    1 AS pending_user,
    COALESCE(u.letters_count, 0) AS letters_count,
    COALESCE(u.diacritic_mark_count, 0) AS diacritic_mark_count
  FROM ${AppConfig.userDictionaryTable} u
  WHERE NOT EXISTS (SELECT 1 FROM ${AppConfig.fullDictionaryTable} f WHERE f.normalized_word = u.word)
    AND $draftWhere
),
combined AS (
  SELECT * FROM full_part
  UNION ALL
  SELECT * FROM draft_part
)
SELECT * FROM combined WHERE 1=1
''';

    if (source == kLexiconSourceDraft) {
      innerSelect += ' AND src = ?';
      args.add(kLexiconSourceDraft);
    } else if (source != null &&
        source.isNotEmpty &&
        source != kLexiconPendingFilter) {
      innerSelect += ' AND src = ?';
      args.add(source);
    }
    if (pendingOnly || source == kLexiconPendingFilter) {
      innerSelect += ' AND pending_user = 1';
    }
    if (language == kLexiconMixedScriptsFilter) {
      innerSelect += '''
 AND (
  (
   EXISTS (
    WITH RECURSIVE idx(i) AS (
      SELECT 1
      UNION ALL
      SELECT i + 1 FROM idx WHERE i < length(display_word)
    )
    SELECT 1 FROM idx
    WHERE (unicode(substr(display_word, i, 1)) BETWEEN 880 AND 1023)
       OR (unicode(substr(display_word, i, 1)) BETWEEN 7936 AND 8191)
    LIMIT 1
  )
  AND EXISTS (
    WITH RECURSIVE idx(i) AS (
      SELECT 1
      UNION ALL
      SELECT i + 1 FROM idx WHERE i < length(display_word)
    )
    SELECT 1 FROM idx
    WHERE (unicode(substr(display_word, i, 1)) BETWEEN 65 AND 90)
       OR (unicode(substr(display_word, i, 1)) BETWEEN 97 AND 122)
    LIMIT 1
  )
  )
  OR lang = '$kLexiconLanguageMix'
)''';
    } else if (language != null && language.isNotEmpty) {
      innerSelect += ' AND lang = ?';
      args.add(language);
    }
    if (category != null && category.isNotEmpty) {
      innerSelect += ' AND cat = ?';
      args.add(category);
    }

    final lcOp = lettersCountOp;
    final lcVal = lettersCountValue;
    if (lcOp != null &&
        (lcOp == '>=' || lcOp == '<=' || lcOp == '=') &&
        lcVal != null &&
        lcVal >= 1 &&
        lcVal <= 100) {
      innerSelect += ' AND letters_count $lcOp ?';
      args.add(lcVal);
    }

    switch (diacriticMarksFilter) {
      case 'none':
        innerSelect += ' AND diacritic_mark_count = 0';
        break;
      case '1':
        innerSelect += ' AND diacritic_mark_count = 1';
        break;
      case '2':
        innerSelect += ' AND diacritic_mark_count = 2';
        break;
      case '3':
        innerSelect += ' AND diacritic_mark_count = 3';
        break;
      case 'gt3':
        innerSelect += ' AND diacritic_mark_count > 3';
        break;
      default:
        break;
    }

    if (countOnly) {
      return (
        'SELECT COUNT(*) AS c FROM ($innerSelect) AS cnt',
        args,
      );
    }

    final limArgs = <Object?>[...args, limit, offset];
    final dataSql =
        '$innerSelect ORDER BY norm_key COLLATE NOCASE LIMIT ? OFFSET ?';
    return (dataSql, limArgs);
  }
}
