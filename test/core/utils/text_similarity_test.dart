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

  group('matchedSpan — μεγαλύτερο κοινό τμήμα ονομάτων', () {
    test('κοινή αρχή: τόνοι και πεζά/κεφαλαία δεν την κόβουν', () {
      expect(
        TextSimilarity.matchedSpan('Βασίλης Δροσούλης', 'Βασίλης Δρόσος'),
        (start: 0, length: 'Βασίλης Δροσο'.length),
      );
    });

    test('εμπεριέχον όνομα: το κοινό τμήμα βρίσκεται και στη μέση', () {
      expect(
        TextSimilarity.matchedSpan('Γραφείο Πληροφορικής', 'Πληροφορική'),
        (start: 'Γραφείο '.length, length: 'Πληροφορική'.length),
      );
      expect(
        TextSimilarity.matchedSpan('Πληροφορική', 'Γραφείο Πληροφορικής'),
        (start: 0, length: 'Πληροφορική'.length),
      );
    });

    test('το τελικό ς ταυτίζεται με σ', () {
      expect(TextSimilarity.matchedSpan('Δρόσος', 'δρόσοΣ'), (
        start: 0,
        length: 6,
      ));
    });

    test('πολύ μικρό κοινό τμήμα (θόρυβος) → κανένα μαρκάρισμα', () {
      expect(TextSimilarity.matchedSpan('Άννα', 'Ελένη'), (
        start: 0,
        length: 0,
      ));
    });

    test('κενές συμβολοσειρές → κανένα μαρκάρισμα', () {
      expect(TextSimilarity.matchedSpan('', 'Άννα'), (start: 0, length: 0));
    });

    test('ταυτόσημα ονόματα → όλο το μήκος', () {
      expect(TextSimilarity.matchedSpan('Άννα Ψαρρά', 'Αννα ψαρρα'), (
        start: 0,
        length: 'Άννα Ψαρρά'.length,
      ));
    });
  });
}
