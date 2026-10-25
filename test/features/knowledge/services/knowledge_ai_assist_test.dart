// Η ΤΝ ως βοηθός της Βάσης Γνώσης: η προτροπή ενός άρθρου, η ανάγνωση της
// απάντησης και το αρχείο «Εξαγωγή για ΤΝ».
//
//   flutter test test/features/knowledge/services/knowledge_ai_assist_test.dart

import 'package:call_logger/features/knowledge/models/knowledge_article.dart';
import 'package:call_logger/features/knowledge/services/knowledge_ai_prompts.dart';
import 'package:call_logger/features/knowledge/services/knowledge_export_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Η προτροπή «Βελτίωση με ΤΝ»', () {
    String build({String template = '', String tags = ''}) =>
        buildKnowledgeImprovePrompt(
          template: template,
          title: 'Αδυναμία προβολής αιτημάτων στο Docutrak',
          symptom: 'Δεν φαίνονται τα αιτήματα',
          solution: 'Αλλαγή κατάστασης σε γνωστοποίηση',
          tags: tags,
        );

    test('συμπληρώνει τα πεδία του άρθρου στην προτροπή του χρήστη', () {
      final prompt = build(template: 'Άρθρο: {Τίτλος} / {Σύμπτωμα} / {Λύση}');

      expect(
        prompt,
        'Άρθρο: Αδυναμία προβολής αιτημάτων στο Docutrak / '
        'Δεν φαίνονται τα αιτήματα / Αλλαγή κατάστασης σε γνωστοποίηση',
      );
    });

    test('χωρίς λέξεις-κλειδιά η γραμμή τους παραλείπεται', () {
      expect(build(), isNot(contains('Τρέχουσες λέξεις-κλειδιά')));
      expect(
        build(tags: 'Docutrak, αιτήματα'),
        contains('Τρέχουσες λέξεις-κλειδιά: Docutrak, αιτήματα'),
      );
    });

    test('κενή προτροπή χρήστη σημαίνει την εργοστασιακή', () {
      expect(build(), startsWith('Βελτίωσε τη διατύπωση'));
      expect(build(), contains('Τίτλος: Αδυναμία προβολής αιτημάτων'));
      expect(
        build(),
        isNot(matches(RegExp(r'\{(Τίτλος|Σύμπτωμα|Λύση|@)'))),
        reason: 'κανένα σήμα και κανένα τμήμα δεν μένει ασυμπλήρωτο',
      );
    });
  });

  group('Η απάντηση της ΤΝ', () {
    test('φέρνει τα τέσσερα πεδία του άρθρου', () {
      final s = parseKnowledgeImproveResponse(
        '{"title":"Τ","symptom":"Σ","solution":"Λ","tags":"α, β"}',
      );

      expect(s?.title, 'Τ');
      expect(s?.symptom, 'Σ');
      expect(s?.solution, 'Λ');
      expect(s?.tags, 'α, β');
    });

    test('λέξεις-κλειδιά ως λίστα γίνονται χωρισμένες με κόμμα', () {
      final s = parseKnowledgeImproveResponse(
        '{"title":"Τ","tags":["Docutrak"," αιτήματα ",""]}',
      );

      expect(s?.tags, 'Docutrak, αιτήματα');
    });

    test('πεδίο που λείπει μένει κενό — η φόρμα το κρατά όπως ήταν', () {
      final s = parseKnowledgeImproveResponse('{"title":"Μόνο τίτλος"}');

      expect(s?.title, 'Μόνο τίτλος');
      expect(s?.solution, isNull);
    });

    test('διαβάζεται και τυλιγμένη σε ```json', () {
      final s = parseKnowledgeImproveResponse('```json\n{"title":"Τ"}\n```');

      expect(s?.title, 'Τ');
    });

    test('απάντηση χωρίς κανένα πεδίο του άρθρου δεν αλλάζει τίποτα', () {
      expect(parseKnowledgeImproveResponse('{"description":"x"}'), isNull);
      expect(parseKnowledgeImproveResponse('όχι JSON'), isNull);
    });
  });

  group('Το αρχείο «Εξαγωγή για ΤΝ»', () {
    final markdown = buildKnowledgeExportMarkdown(
      instruction: 'Πρότεινε συγχωνεύσεις.',
      articles: const [
        KnowledgeArticle(
          id: 6,
          title: 'Docutrak',
          symptom: 'Δεν φαίνονται τα αιτήματα',
          solution: 'Γνωστοποίηση',
        ),
        KnowledgeArticle(
          id: 2,
          title: 'Τεχνητός Νεφρός',
          symptom: 'Ακύρωση περιστατικού',
          solution: 'Από τη διαχείριση',
          tags: 'Medico',
          categoryName: 'Medico',
        ),
      ],
    );

    test('ξεκινά με την οδηγία του χρήστη', () {
      expect(markdown, startsWith('Πρότεινε συγχωνεύσεις.'));
    });

    test('κάθε άρθρο με τον αριθμό του, κατά σειρά αριθμού', () {
      expect(markdown, contains('Άρθρα: 2'));
      expect(
        markdown.indexOf('## Άρθρο 2: Τεχνητός Νεφρός'),
        lessThan(markdown.indexOf('## Άρθρο 6: Docutrak')),
      );
    });

    test('κενά πεδία δεν γράφονται', () {
      final docutrak = markdown.substring(markdown.indexOf('## Άρθρο 6'));
      expect(docutrak, isNot(contains('Λέξεις-κλειδιά:')));
      expect(markdown, isNot(contains('Χρησιμοποιήθηκε')));
      expect(markdown, contains('Κατηγορία: Medico'));
    });
  });
}
