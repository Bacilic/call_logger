// Ο κριτής «ανήκει ακόμη αυτή η γραμμή στη λίστα;» μετά από επεξεργασία.
//
//   flutter test test/features/dictionary/lexicon_row_filter_test.dart

import 'package:call_logger/core/database/dictionary_repository.dart';
import 'package:call_logger/features/dictionary/models/lexicon_list_filters_model.dart';
import 'package:call_logger/features/dictionary/models/lexicon_row_filter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String word = 'Βήτα',
  String norm = 'βητα',
  String src = 'imported',
  String lang = 'el',
  String cat = 'Γενική',
  int pending = 0,
  int letters = 4,
  int marks = 1,
}) => {
  'display_word': word,
  'norm_key': norm,
  'src': src,
  'lang': lang,
  'cat': cat,
  'pending_user': pending,
  'letters_count': letters,
  'diacritic_mark_count': marks,
};

bool _matches(
  Map<String, dynamic> row, {
  LexiconListFiltersModel filters = const LexiconListFiltersModel(),
  String search = '',
  String letters = '',
}) => lexiconRowMatchesFilters(
  row,
  filters: filters,
  search: search,
  lettersText: letters,
);

void main() {
  test('χωρίς φίλτρα κάθε γραμμή ανήκει', () {
    expect(_matches(_row()), isTrue);
  });

  test('η αναζήτηση ταιριάζει στο κλειδί ή στη λέξη, χωρίς πεζά/κεφαλαία', () {
    expect(_matches(_row(), search: 'ΒΗΤ'), isTrue);
    expect(_matches(_row(), search: 'Βήτ'), isTrue);
    expect(_matches(_row(), search: 'αλφα'), isFalse);
  });

  test('«Πρόχειρο» κρατά μόνο πρόχειρα, «Διπλές» μόνο τις διπλές', () {
    const draft = LexiconListFiltersModel(
      sourceFilter: DictionaryRepository.kLexiconSourceDraft,
    );
    const pending = LexiconListFiltersModel(
      sourceFilter: DictionaryRepository.kLexiconPendingFilter,
    );
    expect(_matches(_row(), filters: draft), isFalse);
    expect(_matches(_row(src: 'draft'), filters: draft), isTrue);
    expect(_matches(_row(), filters: pending), isFalse);
    expect(_matches(_row(pending: 1), filters: pending), isTrue);
  });

  test('η «μικτή γραφή» δεν φιλτράρει με τη γλώσσα της γραμμής', () {
    const mixed = LexiconListFiltersModel(
      langFilter: DictionaryRepository.kLexiconMixedScriptsFilter,
    );
    const english = LexiconListFiltersModel(langFilter: 'en');
    expect(_matches(_row(), filters: mixed), isTrue);
    expect(_matches(_row(), filters: english), isFalse);
  });

  test('ο αριθμός γραμμάτων μετρά μόνο από 1 έως 100', () {
    const atLeast = LexiconListFiltersModel(lettersCompareOp: '>=');
    expect(_matches(_row(letters: 4), filters: atLeast, letters: '5'), isFalse);
    expect(_matches(_row(letters: 5), filters: atLeast, letters: '5'), isTrue);
    expect(_matches(_row(letters: 4), filters: atLeast, letters: '0'), isTrue);
    expect(
      _matches(_row(letters: 4), filters: atLeast, letters: '101'),
      isTrue,
    );
  });

  test('ο τόνος: «κανένα», ακριβής αριθμός, και «περισσότερα από 3»', () {
    expect(
      _matches(
        _row(marks: 0),
        filters: const LexiconListFiltersModel(diacriticMarksFilter: 'none'),
      ),
      isTrue,
    );
    expect(
      _matches(
        _row(marks: 1),
        filters: const LexiconListFiltersModel(diacriticMarksFilter: '2'),
      ),
      isFalse,
    );
    expect(
      _matches(
        _row(marks: 4),
        filters: const LexiconListFiltersModel(diacriticMarksFilter: 'gt3'),
      ),
      isTrue,
    );
  });
}
