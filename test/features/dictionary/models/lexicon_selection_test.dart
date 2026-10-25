// Η επιλογή λέξεων του Λεξικού για «Έλεγχο με ΤΝ»: κλικ, Shift + κλικ,
// σελίδα, και η σειρά με την οποία φεύγουν οι λέξεις.
//
//   flutter test test/features/dictionary/models/lexicon_selection_test.dart

import 'package:call_logger/features/dictionary/models/lexicon_selection.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(int id, String word) => {
  'entry_id': id,
  'norm_key': word,
  'display_word': word,
};

final _page = [
  _row(1, 'abc'),
  _row(2, 'abu'),
  _row(3, 'ace'),
  _row(4, 'acl'),
  _row(5, 'act'),
];

List<String> _words(LexiconSelection s) =>
    s.rows.values.map((r) => r['display_word'] as String).toList();

void main() {
  test('κλικ στο κουτάκι βάζει τη λέξη, δεύτερο κλικ τη βγάζει', () {
    final once = const LexiconSelection().toggle(_page[1]);
    expect(_words(once), ['abu']);
    expect(once.toggle(_page[1]).isEmpty, isTrue);
  });

  test('Shift + κλικ επιλέγει από το προηγούμενο κλικ ως εδώ', () {
    final s = const LexiconSelection()
        .toggle(_page[1])
        .selectRange(_page, _page[3]);
    expect(_words(s), ['abu', 'ace', 'acl']);
  });

  test('Shift + κλικ προς τα πάνω επιλέγει την ίδια περιοχή', () {
    final s = const LexiconSelection()
        .toggle(_page[3])
        .selectRange(_page, _page[1]);
    expect(_words(s).toSet(), {'abu', 'ace', 'acl'});
  });

  test('Shift + κλικ χωρίς προηγούμενο κλικ στη σελίδα μετρά απλό κλικ', () {
    final otherPage = [_row(9, 'zzz')];
    final s = const LexiconSelection()
        .toggle(otherPage.first)
        .selectRange(_page, _page[2]);
    expect(_words(s), ['zzz', 'ace']);
  });

  test('η επιλογή κρατά αντίγραφα — επιβιώνει της αλλαγής σελίδας', () {
    final s = const LexiconSelection().addAll(_page.take(2));
    final nextPage = [_row(6, 'ada'), _row(7, 'add')];
    final both = s.addAll(nextPage);
    expect(_words(both), ['abc', 'abu', 'ada', 'add']);
  });

  test('η αποστολή παίρνει τις πρώτες με τη σειρά επιλογής', () {
    final s = const LexiconSelection().toggle(_page[4]).addAll(_page).removeAll(
      [_page[0]],
    );
    expect(s.firstBatch(2).map((r) => r['display_word']), ['act', 'abu']);
  });

  test('το κουτάκι της σελίδας: όλες, καμία ή μερικές', () {
    const empty = LexiconSelection();
    expect(empty.pageState(_page), isFalse);
    expect(empty.addAll(_page).pageState(_page), isTrue);
    expect(empty.toggle(_page[0]).pageState(_page), isNull);
  });

  test('πρόχειρο χωρίς αριθμό εγγραφής ξεχωρίζει από το κλειδί του', () {
    final draft = {'entry_id': null, 'norm_key': 'δελτα'};
    expect(lexiconRowKey(draft), isNot(lexiconRowKey(_row(1, 'δελτα'))));
  });
}
