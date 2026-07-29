import 'package:call_logger/core/utils/text_similarity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextSimilarity', () {
    test('ακριβής ταύτιση μετά κανονικοποίηση → 100', () {
      expect(
        TextSimilarity.score('Γιωργος Παπαδοπουλος', 'Γιώργος Παπαδόπουλος'),
        100,
      );
    });

    test('κενό → 0', () {
      expect(TextSimilarity.score('', 'Γιώργος'), 0);
      expect(TextSimilarity.score('Γιώργος', '  '), 0);
    });

    test('containment → containmentScore', () {
      expect(TextSimilarity.score('Παπαδόπουλος', 'Γιώργος Παπαδόπουλος'), 72);
      expect(
        TextSimilarity.score(
          'Παπαδόπουλος',
          'Γιώργος Παπαδόπουλος',
          containmentScore: 40,
        ),
        40,
      );
    });

    test('ανάστροφη σειρά λέξεων → υψηλό score κάτω από 100', () {
      final score = TextSimilarity.score('Βασίλης Δρόσος', 'Δρόσος Βασίλης');
      expect(score, greaterThanOrEqualTo(90));
      expect(score, lessThan(100));
    });

    test('levenshtein — ίδια συμβολοσειρά → 0', () {
      expect(TextSimilarity.levenshtein('abc', 'abc'), 0);
    });

    test('levenshtein — μία αντικατάσταση → 1', () {
      expect(TextSimilarity.levenshtein('abc', 'abd'), 1);
    });

    test('normalize αφαιρεί τόνους και σημεία', () {
      expect(
        TextSimilarity.normalize('Γιώργος-Παπαδόπουλος'),
        TextSimilarity.normalize('γιωργος παπαδοπουλος'),
      );
    });
  });
}
