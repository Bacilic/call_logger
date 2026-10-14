import '../../../core/database/dictionary_repository.dart';
import 'lexicon_list_filters_model.dart';

/// Ανήκει ακόμη αυτή η γραμμή στη λίστα που βλέπει ο χρήστης;
///
/// Ρωτιέται μετά από επεξεργασία μιας λέξης, για να αποφασιστεί αν η γραμμή
/// μένει στη θέση της ή φεύγει — χωρίς να ξαναφορτωθεί όλη η λίστα από τη
/// βάση. Γι' αυτό οφείλει να κρίνει με τα ίδια φίλτρα που χρησιμοποιεί το
/// ερώτημα της λίστας ([LexiconListQuery]).
///
/// [search] και [lettersText] είναι τα κείμενα των πεδίων της οθόνης, όπως
/// πληκτρολογήθηκαν.
bool lexiconRowMatchesFilters(
  Map<String, dynamic> row, {
  required LexiconListFiltersModel filters,
  required String search,
  required String lettersText,
}) {
  final needleSource = search.trim();
  if (needleSource.isNotEmpty) {
    final normKey = (row['norm_key'] as String? ?? '').toLowerCase();
    final display = (row['display_word'] as String? ?? '').toLowerCase();
    final needle = needleSource.toLowerCase();
    if (!normKey.contains(needle) && !display.contains(needle)) {
      return false;
    }
  }

  final category = filters.categoryFilter;
  if (category != null && category.isNotEmpty) {
    if ((row['cat'] as String? ?? '') != category) return false;
  }

  final src = row['src'] as String? ?? '';
  final pending = (row['pending_user'] as int? ?? 0) == 1;
  final sourceFilter = filters.sourceFilter;
  if (sourceFilter == DictionaryRepository.kLexiconSourceDraft) {
    if (src != DictionaryRepository.kLexiconSourceDraft) return false;
  } else if (sourceFilter == DictionaryRepository.kLexiconPendingFilter) {
    if (!pending) return false;
  } else if (sourceFilter != null && sourceFilter.isNotEmpty) {
    if (src != sourceFilter) return false;
  }

  final langFilter = filters.langFilter;
  if (langFilter != null &&
      langFilter.isNotEmpty &&
      langFilter != DictionaryRepository.kLexiconMixedScriptsFilter) {
    if ((row['lang'] as String? ?? '') != langFilter) return false;
  }

  if (!_rowPassesLettersFilter(row, filters, lettersText) ||
      !_rowPassesDiacriticFilter(row, filters)) {
    return false;
  }
  return true;
}

bool _rowPassesLettersFilter(
  Map<String, dynamic> row,
  LexiconListFiltersModel filters,
  String lettersText,
) {
  final text = lettersText.trim();
  if (text.isEmpty) return true;
  final parsed = int.tryParse(text);
  if (parsed == null || parsed < 1 || parsed > 100) return true;
  final lettersCount = row['letters_count'] as int? ?? 0;
  return switch (filters.lettersCompareOp) {
    '>=' => lettersCount >= parsed,
    '<=' => lettersCount <= parsed,
    '=' => lettersCount == parsed,
    _ => true,
  };
}

bool _rowPassesDiacriticFilter(
  Map<String, dynamic> row,
  LexiconListFiltersModel filters,
) {
  final filter = filters.diacriticMarksFilter;
  if (filter == null || filter.isEmpty) return true;
  final count = row['diacritic_mark_count'] as int? ?? 0;
  return switch (filter) {
    'none' => count == 0,
    '1' => count == 1,
    '2' => count == 2,
    '3' => count == 3,
    'gt3' => count > 3,
    _ => true,
  };
}
