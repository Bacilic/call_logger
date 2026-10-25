// Ο «Έλεγχος με ΤΝ» του Λεξικού χωρίς δίκτυο: η προτροπή, η ανάγνωση της
// απάντησης και το τι προτείνεται στον χρήστη για κάθε λέξη.
//
//   flutter test test/features/dictionary/services/lexicon_ai_review_test.dart

import 'package:call_logger/features/dictionary/services/lexicon_ai_prompts.dart';
import 'package:call_logger/features/dictionary/services/lexicon_review_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(int id, String word, String norm) => {
  'entry_id': id,
  'display_word': word,
  'norm_key': norm,
  'src': 'imported',
};

void main() {
  group('Η προτροπή', () {
    test('οι λέξεις μπαίνουν αριθμημένες, μία σε κάθε γραμμή', () {
      final prompt = buildLexiconReviewPrompt(
        template: 'Έλεγξε:\n{Λέξεις}',
        words: ['abc', ' ρυθμίστικε '],
      );
      expect(prompt, 'Έλεγξε:\n1. abc\n2. ρυθμίστικε');
    });

    test('κενή προτροπή χρήστη σημαίνει την εργοστασιακή', () {
      final prompt = buildLexiconReviewPrompt(template: '', words: ['abc']);
      expect(prompt, startsWith('Είσαι επιμελητής του λεξικού'));
      expect(prompt, contains('1. abc'));
      expect(prompt, isNot(contains('{Λέξεις}')));
    });
  });

  group('Η απάντηση της ΤΝ', () {
    test('διαβάζει ετυμηγορία, σωστή μορφή και βεβαιότητα ανά αριθμό', () {
      final verdicts = parseLexiconReviewResponse(
        '{"results":['
        '{"n":1,"verdict":"correct","suggestion":"","sure":true},'
        '{"n":"2","verdict":"fix","suggestion":"ρυθμίστηκε","sure":true},'
        '{"n":3,"verdict":"delete","sure":false}]}',
        wordCount: 3,
      )!;
      expect(verdicts[1]!.kind, LexiconAiVerdictKind.correct);
      expect(verdicts[2]!.suggestion, 'ρυθμίστηκε');
      expect(verdicts[3]!.kind, LexiconAiVerdictKind.delete);
      expect(verdicts[3]!.sure, isFalse);
    });

    test('ό,τι δεν διαβάζεται με βεβαιότητα παραλείπεται', () {
      final verdicts = parseLexiconReviewResponse(
        '{"results":['
        '{"n":1,"verdict":"maybe"},'
        '{"n":2,"verdict":"fix","suggestion":""},'
        '{"n":9,"verdict":"delete","sure":true},'
        '{"n":3,"verdict":"delete"}]}',
        wordCount: 3,
      )!;
      expect(verdicts.keys, [3]);
      expect(verdicts[3]!.sure, isFalse, reason: 'χωρίς "sure" θέλει ματιά');
    });

    test('απάντηση χωρίς ούτε μία ετυμηγορία δεν αλλάζει τίποτα', () {
      expect(parseLexiconReviewResponse('{"x":1}', wordCount: 3), isNull);
      expect(parseLexiconReviewResponse('όχι JSON', wordCount: 3), isNull);
    });
  });

  group('Τι προτείνεται για κάθε λέξη', () {
    final rows = [
      _row(1, 'abc', 'abc'),
      _row(2, 'ρυθμίστικε', 'ρυθμιστικε'),
      _row(3, 'αγκ', 'αγκ'),
      _row(4, 'Γαμα', 'γαμα'),
      _row(5, 'xyz', 'xyz'),
    ];

    Future<List<LexiconReviewItem>> plan(Map<int, LexiconAiVerdict> v) =>
        planLexiconReview(
          rows: rows,
          verdicts: v,
          // Η «Γάμμα» υπάρχει ήδη ως εγγραφή 40.
          existingEntryId: (key) async => key == 'γαμμα' ? 40 : null,
        );

    test(
      'πρώτα ό,τι αλλάζει, μετά οι σωστές, στο τέλος οι αναπάντητες',
      () async {
        final items = await plan({
          1: const LexiconAiVerdict(
            kind: LexiconAiVerdictKind.correct,
            sure: true,
          ),
          2: const LexiconAiVerdict(
            kind: LexiconAiVerdictKind.fix,
            suggestion: 'ρυθμίστηκε',
            sure: true,
          ),
          3: const LexiconAiVerdict(
            kind: LexiconAiVerdictKind.delete,
            sure: true,
          ),
          4: const LexiconAiVerdict(
            kind: LexiconAiVerdictKind.fix,
            suggestion: 'Γάμμα',
            sure: true,
          ),
        });
        expect(items.map((i) => (i.word, i.action)), [
          ('ρυθμίστικε', LexiconReviewAction.fix),
          ('Γαμα', LexiconReviewAction.deleteDuplicate),
          ('αγκ', LexiconReviewAction.delete),
          ('abc', LexiconReviewAction.approve),
          ('xyz', LexiconReviewAction.none),
        ]);
        expect(items.last.applicable, isFalse);
      },
    );

    test('διόρθωση προς την ίδια γραφή είναι έγκριση', () async {
      final items = await plan({
        1: const LexiconAiVerdict(
          kind: LexiconAiVerdictKind.fix,
          suggestion: 'abc',
          sure: true,
        ),
      });
      expect(items.first.action, LexiconReviewAction.approve);
    });

    test('διόρθωση μόνο στον τόνο μένει διόρθωση της ίδιας λέξης', () async {
      final items = await planLexiconReview(
        rows: [_row(7, 'Γάμμα', 'γαμμα')],
        verdicts: {
          1: const LexiconAiVerdict(
            kind: LexiconAiVerdictKind.fix,
            suggestion: 'Γαμμά',
            sure: true,
          ),
        },
        existingEntryId: (key) async => 7,
      );
      expect(items.single.action, LexiconReviewAction.fix);
    });

    test(
      'τσεκαρισμένα από την αρχή μόνο όσα η ΤΝ έκρινε με βεβαιότητα',
      () async {
        final items = await plan({
          1: const LexiconAiVerdict(
            kind: LexiconAiVerdictKind.correct,
            sure: true,
          ),
          3: const LexiconAiVerdict(
            kind: LexiconAiVerdictKind.delete,
            sure: false,
          ),
        });
        final byWord = {for (final i in items) i.word: i};
        expect(byWord['abc']!.preselected, isTrue);
        expect(byWord['αγκ']!.preselected, isFalse);
        expect(byWord['xyz']!.preselected, isFalse);
      },
    );
  });
}
