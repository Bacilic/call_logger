import '../../../core/database/dictionary_repository.dart';
import '../models/lexicon_list_filters_model.dart';

/// Τα κριτήρια της λίστας του λεξικού, φτιαγμένα **μία φορά** από τα φίλτρα
/// και τα πεδία της οθόνης.
///
/// Το πλήθος και οι σελίδες ρωτούν τη βάση με το ίδιο αντικείμενο, ώστε να μην
/// μπορούν να αποκλίνουν: ένα «Σύνολο» που μετρά με άλλα κριτήρια από τις
/// γραμμές που δείχνει θα έλεγε ψέματα.
class LexiconListQuery {
  const LexiconListQuery._({
    required this.language,
    required this.source,
    required this.category,
    required this.normalizedSearch,
    required this.pendingOnly,
    required this.lettersCountOp,
    required this.lettersCountValue,
    required this.diacriticMarksFilter,
  });

  /// [search] και [lettersText] είναι τα κείμενα των πεδίων της οθόνης. Ο
  /// αριθμός γραμμάτων μετρά μόνο όταν είναι ακέραιος από 1 έως 100.
  factory LexiconListQuery.from(
    LexiconListFiltersModel filters, {
    required String search,
    required String lettersText,
  }) {
    final trimmedSearch = search.trim();
    String? lettersOp;
    int? lettersVal;
    final letters = lettersText.trim();
    if (letters.isNotEmpty) {
      final parsed = int.tryParse(letters);
      if (parsed != null && parsed >= 1 && parsed <= 100) {
        lettersOp = filters.lettersCompareOp;
        lettersVal = parsed;
      }
    }
    return LexiconListQuery._(
      language: filters.langFilter,
      source: filters.sourceFilter,
      category: filters.categoryFilter,
      normalizedSearch: trimmedSearch.isEmpty ? null : trimmedSearch,
      pendingOnly:
          filters.sourceFilter == DictionaryRepository.kLexiconPendingFilter,
      lettersCountOp: lettersOp,
      lettersCountValue: lettersVal,
      diacriticMarksFilter: filters.diacriticMarksFilter,
    );
  }

  final String? language;
  final String? source;
  final String? category;
  final String? normalizedSearch;
  final bool pendingOnly;
  final String? lettersCountOp;
  final int? lettersCountValue;
  final String? diacriticMarksFilter;

  Future<int> count(DictionaryRepository repository) =>
      repository.countCombinedLexiconRows(
        language: language,
        source: source,
        category: category,
        normalizedSearch: normalizedSearch,
        pendingOnly: pendingOnly,
        lettersCountOp: lettersCountOp,
        lettersCountValue: lettersCountValue,
        diacriticMarksFilter: diacriticMarksFilter,
      );

  Future<List<Map<String, dynamic>>> page(
    DictionaryRepository repository, {
    required int limit,
    required int offset,
  }) => repository.queryCombinedLexiconPage(
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
  );
}
