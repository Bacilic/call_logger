// Οι φορτώσεις της λίστας του Λεξικού: μόνο η πιο πρόσφατη γράφει στη λίστα.
// Σε βάση δικτύου μια αργή παρτίδα δεν πρέπει να προσθέτει λέξεις του παλιού
// φίλτρου στη νέα λίστα.
//
//   flutter test test/features/dictionary/lexicon_list_loader_test.dart

import 'dart:async';

import 'package:call_logger/features/dictionary/services/lexicon_list_loader.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> _words(List<String> words) => [
  for (final w in words) {'word': w},
];

void main() {
  test('αργή παρτίδα του παλιού φίλτρου δεν μπαίνει στη νέα λίστα', () async {
    final loader = LexiconListLoader();
    final slowBatch = Completer<List<Map<String, dynamic>>>();

    // Κύλιση στο τέλος της «αλ…»: ζητείται η επόμενη παρτίδα, αργεί.
    final more = loader.loadMore(offset: 40, page: (_) => slowBatch.future);

    // Ο χρήστης γράφει «βητα»: η νέα λίστα φτάνει αμέσως.
    final fresh = await loader.reload(
      count: () async => 1,
      offsetFor: (_) async => 0,
      page: (_) async => _words(['Βήτα']),
    );
    expect(fresh!.rows, _words(['Βήτα']));

    // Η παλιά παρτίδα φτάνει τώρα — πρέπει να πεταχτεί.
    slowBatch.complete(_words(['Αλφάβητο', 'Αλκυόνη']));
    expect(await more, isNull);
  });

  test(
    'δύο αναζητήσεις στη σειρά: κερδίζει η τελευταία, όχι η πιο αργή',
    () async {
      final loader = LexiconListLoader();
      final slowCount = Completer<int>();

      final first = loader.reload(
        count: () => slowCount.future,
        offsetFor: (_) async => 0,
        page: (_) async => _words(['Αλφα']),
      );
      final second = await loader.reload(
        count: () async => 1,
        offsetFor: (_) async => 0,
        page: (_) async => _words(['Βήτα']),
      );
      slowCount.complete(1);

      expect(second!.rows, _words(['Βήτα']));
      expect(await first, isNull);
    },
  );

  test('παρτίδα χωρίς ενδιάμεση αλλαγή φίλτρου εφαρμόζεται κανονικά', () async {
    final loader = LexiconListLoader();
    await loader.reload(
      count: () async => 80,
      offsetFor: (_) async => 0,
      page: (_) async => _words(['Αλφα']),
    );
    final more = await loader.loadMore(
      offset: 40,
      page: (_) async => _words(['Αλφάβητο']),
    );
    expect(more, _words(['Αλφάβητο']));
  });
}
