import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/knowledge/models/knowledge_article.dart';
import '../../features/knowledge/services/knowledge_matcher.dart';
import '../utils/search_text_normalizer.dart';
import 'audit_service.dart';

/// Repository της Βάσης Γνώσης (πίνακας `knowledge_base`).
///
/// Τα άρθρα είναι λίγα και μακρόβια — δεκάδες, όχι χιλιάδες. Γι' αυτό το
/// ταίριασμα γίνεται στη μνήμη με [KnowledgeMatcher] αντί για SQL: η λογική
/// βαθμολόγησης είναι καθαρή συνάρτηση που ελέγχεται χωρίς βάση, και το κόστος
/// της φόρτωσης όλων των άρθρων είναι αμελητέο σε αυτή την κλίμακα.
class KnowledgeBaseRepository {
  const KnowledgeBaseRepository(this.db);

  final Database db;

  static const List<String> _auditedFields = [
    'topic',
    'symptom',
    'content',
    'tags',
    'category_id',
  ];

  static const String _selectWithCategory = '''
    SELECT kb.*, cat.name AS category_name
    FROM knowledge_base kb
    LEFT JOIN categories cat ON cat.id = kb.category_id
  ''';

  /// Το κείμενο πάνω στο οποίο δουλεύει η αναζήτηση της οθόνης.
  static String buildSearchIndex(KnowledgeArticle article) {
    final parts = <String>[
      article.title,
      article.symptom,
      article.solution,
      article.tags,
    ].where((part) => part.trim().isNotEmpty);
    return SearchTextNormalizer.normalizeForSearch(parts.join(' '));
  }

  /// Όλα τα άρθρα, νεότερα πρώτα· με [keyword] φιλτράρονται στο ευρετήριο.
  Future<List<KnowledgeArticle>> listArticles({
    String? keyword,
    int? categoryId,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    final normalized = SearchTextNormalizer.normalizeForSearch(keyword ?? '');
    if (normalized.isNotEmpty) {
      for (final token in normalized.split(' ')) {
        if (token.isEmpty) continue;
        clauses.add('kb.search_index LIKE ?');
        args.add('%$token%');
      }
    }
    if (categoryId != null) {
      clauses.add('kb.category_id = ?');
      args.add(categoryId);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = await db.rawQuery(
      '$_selectWithCategory $where ORDER BY kb.updated_at DESC, kb.id DESC',
      args,
    );
    return rows.map(KnowledgeArticle.fromMap).toList();
  }

  Future<KnowledgeArticle?> getById(int id) async {
    final rows = await db.rawQuery(
      '$_selectWithCategory WHERE kb.id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return KnowledgeArticle.fromMap(rows.first);
  }

  /// Τα άρθρα που ταιριάζουν με μια περιγραφή προβλήματος.
  ///
  /// Το [query] είναι το **ωμό** κείμενο της κλήσης, όχι το εξευγενισμένο: τα
  /// άρθρα κρατούν το σύμπτωμα στη γλώσσα του καλούντα ακριβώς για να ταιριάζει
  /// με αυτό που μόλις ακούστηκε στο τηλέφωνο.
  Future<List<KnowledgeArticle>> findRelevant({
    required String query,
    int? categoryId,
    int limit = 3,
  }) async {
    if (query.trim().isEmpty && categoryId == null) {
      return const <KnowledgeArticle>[];
    }
    final all = await listArticles();
    return KnowledgeMatcher.rank(
      articles: all,
      query: query,
      categoryId: categoryId,
      limit: limit,
    ).map((scored) => scored.article).toList();
  }

  /// Το άρθρο που περιγράφει ήδη αυτό το πρόβλημα, αν υπάρχει.
  ///
  /// Αυστηρότερο κατώφλι από το [findRelevant]: εδώ μια λάθος ταύτιση οδηγεί
  /// σε αντικατάσταση δουλεμένης λύσης, όχι απλώς σε μια άσχετη πρόταση.
  Future<KnowledgeArticle?> findDuplicate({
    required String query,
    int? categoryId,
  }) async {
    if (query.trim().isEmpty) return null;
    return KnowledgeMatcher.findDuplicate(
      articles: await listArticles(),
      query: query,
      categoryId: categoryId,
    );
  }

  /// Δημιουργεί ή ενημερώνει άρθρο και επιστρέφει το id του.
  Future<int> saveArticle(KnowledgeArticle article) async {
    final nowIso = DateTime.now().toIso8601String();
    final payload = <String, Object?>{
      ...article.toWriteMap(),
      'search_index': buildSearchIndex(article),
      'updated_at': nowIso,
    };

    return db.transaction<int>((txn) async {
      final user = await AuditService.performingUser(txn);
      final id = article.id;
      if (id == null) {
        payload['created_at'] = nowIso;
        payload['times_used'] = 0;
        final newId = await txn.insert('knowledge_base', payload);
        await AuditService.log(
          txn,
          action: 'ΔΗΜΙΟΥΡΓΙΑ ΑΡΘΡΟΥ ΓΝΩΣΗΣ',
          userPerforming: user,
          details: 'knowledge_base id=$newId',
          entityType: AuditEntityTypes.knowledge,
          entityId: newId,
          entityName: article.title.trim().isEmpty
              ? null
              : article.title.trim(),
          newValues: <String, dynamic>{
            for (final field in _auditedFields)
              if (payload[field] != null) field: payload[field],
          },
        );
        return newId;
      }

      final oldRows = await txn.query(
        'knowledge_base',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (oldRows.isEmpty) return id;
      final oldRow = oldRows.first;

      await txn.update(
        'knowledge_base',
        payload,
        where: 'id = ?',
        whereArgs: [id],
      );

      final oldValues = <String, dynamic>{};
      final newValues = <String, dynamic>{};
      for (final field in _auditedFields) {
        final a = oldRow[field];
        final b = payload[field];
        if (a?.toString() != b?.toString()) {
          oldValues[field] = a;
          newValues[field] = b;
        }
      }
      if (newValues.isEmpty) return id;

      await AuditService.log(
        txn,
        action: 'ΤΡΟΠΟΠΟΙΗΣΗ ΑΡΘΡΟΥ ΓΝΩΣΗΣ',
        userPerforming: user,
        details: 'knowledge_base id=$id',
        entityType: AuditEntityTypes.knowledge,
        entityId: id,
        entityName: article.title.trim().isEmpty ? null : article.title.trim(),
        oldValues: oldValues,
        newValues: newValues,
      );
      return id;
    });
  }

  /// Διαγράφει άρθρο, κρατώντας το περιεχόμενό του στο Ιστορικό.
  ///
  /// Χωρίς soft delete: ένα άρθρο δεν έχει συσχετίσεις που να χάνονται, και ο
  /// σκοπός της συντήρησης είναι ακριβώς να μικραίνει η βάση. Το «πριν» μένει
  /// ολόκληρο στο Ιστορικό Εφαρμογής, οπότε τίποτα δεν εξαφανίζεται αθόρυβα.
  Future<void> deleteArticle(int id) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'knowledge_base',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final row = rows.first;
      final user = await AuditService.performingUser(txn);
      await txn.delete('knowledge_base', where: 'id = ?', whereArgs: [id]);
      await AuditService.log(
        txn,
        action: 'ΔΙΑΓΡΑΦΗ ΑΡΘΡΟΥ ΓΝΩΣΗΣ',
        userPerforming: user,
        details: 'knowledge_base id=$id',
        entityType: AuditEntityTypes.knowledge,
        entityId: id,
        entityName: (row['topic'] as String?)?.trim(),
        oldValues: <String, dynamic>{
          for (final field in _auditedFields)
            if (row[field] != null) field: row[field],
        },
      );
    });
  }

  /// Σημειώνει ότι τα άρθρα χρησιμοποιήθηκαν σε πραγματικό περιστατικό.
  ///
  /// Ο μετρητής είναι το μόνο σήμα ποιότητας που δεν χρειάζεται να δηλώσει
  /// κανείς: όσα άρθρα ξαναχρησιμοποιούνται ανεβαίνουν μόνα τους. Δεν περνά από
  /// Ιστορικό — δεν είναι αλλαγή περιεχομένου, είναι στατιστικό.
  Future<void> markUsed(List<int> articleIds) async {
    final ids = articleIds.toSet().toList();
    if (ids.isEmpty) return;
    final nowIso = DateTime.now().toIso8601String();
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE knowledge_base SET times_used = times_used + 1, last_used_at = ? '
      'WHERE id IN ($placeholders)',
      <Object?>[nowIso, ...ids],
    );
  }

  Future<int> countArticles() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM knowledge_base',
    );
    final value = rows.first['c'];
    return value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
