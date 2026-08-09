import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/knowledge_base_repository.dart';
import '../models/knowledge_article.dart';

/// Το κείμενο αναζήτησης της οθόνης Βάσης Γνώσης.
class KnowledgeSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final knowledgeSearchProvider =
    NotifierProvider<KnowledgeSearchNotifier, String>(
      KnowledgeSearchNotifier.new,
    );

/// Φίλτρο κατηγορίας· `null` σημαίνει «όλες».
class KnowledgeCategoryFilterNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? categoryId) => state = categoryId;
}

final knowledgeCategoryFilterProvider =
    NotifierProvider<KnowledgeCategoryFilterNotifier, int?>(
      KnowledgeCategoryFilterNotifier.new,
    );

/// Μετρητής ανανέωσης: κάθε αποθήκευση/διαγραφή τον αυξάνει, ώστε η λίστα να
/// ξαναδιαβάζει χωρίς να χρειάζεται ο καλών να ξέρει ποιον provider να ακυρώσει.
class KnowledgeRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final knowledgeRevisionProvider =
    NotifierProvider<KnowledgeRevisionNotifier, int>(
      KnowledgeRevisionNotifier.new,
    );

final knowledgeRepositoryProvider = FutureProvider<KnowledgeBaseRepository>((
  ref,
) async {
  final db = await DatabaseHelper.instance.database;
  return KnowledgeBaseRepository(db);
});

/// Η λίστα άρθρων όπως τη βλέπει η οθόνη, με τα τρέχοντα φίλτρα.
final knowledgeArticlesProvider =
    FutureProvider.autoDispose<List<KnowledgeArticle>>((ref) async {
      ref.watch(knowledgeRevisionProvider);
      final keyword = ref.watch(knowledgeSearchProvider);
      final categoryId = ref.watch(knowledgeCategoryFilterProvider);
      final repo = await ref.watch(knowledgeRepositoryProvider.future);
      return repo.listArticles(keyword: keyword, categoryId: categoryId);
    });

/// Τα σχετικά άρθρα για μια περιγραφή προβλήματος.
///
/// Το ερώτημα είναι το **ωμό** κείμενο της κλήσης μαζί με την κατηγορία της.
typedef KnowledgeLookup = ({String query, int? categoryId});

final relevantKnowledgeProvider = FutureProvider.autoDispose
    .family<List<KnowledgeArticle>, KnowledgeLookup>((ref, lookup) async {
      ref.watch(knowledgeRevisionProvider);
      final repo = await ref.watch(knowledgeRepositoryProvider.future);
      return repo.findRelevant(
        query: lookup.query,
        categoryId: lookup.categoryId,
      );
    });

/// Οι εγγραφές της Βάσης Γνώσης, με την ανανέωση της λίστας δεμένη μέσα.
///
/// Το UI δεν αγγίζει repository και δεν χρειάζεται να θυμάται ποιον provider να
/// ακυρώσει μετά από κάθε αλλαγή — αν το ξεχνούσε, η οθόνη θα έδειχνε το παλιό
/// άρθρο αμέσως μετά την αποθήκευσή του.
class KnowledgeActionsNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<KnowledgeBaseRepository> get _repo =>
      ref.read(knowledgeRepositoryProvider.future);

  void _bumpRevision() => ref.read(knowledgeRevisionProvider.notifier).bump();

  /// Δημιουργεί ή ενημερώνει άρθρο· επιστρέφει το id του.
  Future<int> save(KnowledgeArticle article) async {
    final id = await (await _repo).saveArticle(article);
    _bumpRevision();
    return id;
  }

  Future<void> delete(int id) async {
    await (await _repo).deleteArticle(id);
    _bumpRevision();
  }

  /// Σημειώνει ότι τα άρθρα βοήθησαν σε πραγματικό περιστατικό.
  Future<void> markUsed(List<int> articleIds) async {
    if (articleIds.isEmpty) return;
    await (await _repo).markUsed(articleIds);
    _bumpRevision();
  }
}

final knowledgeActionsProvider =
    NotifierProvider<KnowledgeActionsNotifier, void>(
      KnowledgeActionsNotifier.new,
    );
