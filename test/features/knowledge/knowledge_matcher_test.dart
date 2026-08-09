// Το ταίριασμα κλήσης με άρθρο Βάσης Γνώσης: δουλεύει πάνω σε τηλεγραφικό και
// ανορθόγραφο κείμενο, γιατί έτσι ακούγεται το πρόβλημα στο τηλέφωνο.
//
//   flutter test test/features/knowledge/knowledge_matcher_test.dart

import 'package:call_logger/features/knowledge/models/knowledge_article.dart';
import 'package:call_logger/features/knowledge/services/knowledge_matcher.dart';
import 'package:call_logger/features/knowledge/services/knowledge_prompt_context.dart';
import 'package:flutter_test/flutter_test.dart';

const _vnc = KnowledgeArticle(
  id: 1,
  title: 'Μαύρη οθόνη λόγω ενεργής συνεδρίας VNC',
  symptom: 'Βλέπει μαύρη οθόνη από το πρωί',
  solution:
      'Η μαύρη οθόνη οφείλεται σε ενεργή συνεδρία VNC. Αποσύνδεση του χρήστη '
      'και η προβολή αποκαθίσταται.',
  tags: 'VNC, μαύρη οθόνη',
  categoryId: 7,
  timesUsed: 4,
);

const _bigov = KnowledgeArticle(
  id: 2,
  title: 'Αδυναμία εξαγωγής δεδομένων από bi.gov',
  symptom: 'Εξαγωγή δεδομένων από bi.gov δεν γίνεται',
  solution: 'Εξαγωγή του πίνακα σε Excel και εκτύπωση από εκεί.',
  tags: 'bi.gov, εξαγωγή',
  categoryId: 3,
  timesUsed: 1,
);

const _printer = KnowledgeArticle(
  id: 3,
  title: 'Δεν εκτυπώνει',
  symptom: 'Δεν εκτυπωνει',
  solution: 'Επανεκκίνηση ουράς εκτύπωσης.',
  tags: 'εκτυπωτής',
  timesUsed: 9,
);

void main() {
  group('significantTokens', () {
    test('πετά τις κοινότοπες λέξεις και τις πολύ κοντές', () {
      final tokens = KnowledgeMatcher.significantTokens(
        'Δεν μπορει να δει την οθονη του',
      );
      expect(tokens, isNot(contains('δεν')));
      expect(tokens, isNot(contains('την')));
      expect(tokens, contains('οθονη'));
      expect(tokens, contains('μπορει'));
    });

    test('κρατά τους αριθμούς ακόμη και διψήφιους', () {
      expect(
        KnowledgeMatcher.significantTokens('υπολογιστης 5151 στο 12'),
        containsAll(<String>['5151', '12']),
      );
    });

    test('αγνοεί τόνους και σημεία στίξης', () {
      expect(
        KnowledgeMatcher.significantTokens('Μαύρη οθόνη!!!'),
        KnowledgeMatcher.significantTokens('μαυρη οθονη'),
      );
    });
  });

  group('score', () {
    test('ανορθόγραφο σύμπτωμα βρίσκει το άρθρο', () {
      expect(
        KnowledgeMatcher.score(article: _vnc, query: 'Βλεπει μαυρη οθονη'),
        greaterThan(0),
      );
    });

    test('η ίδια κατηγορία ανεβάζει τη βαθμολογία', () {
      final withCategory = KnowledgeMatcher.score(
        article: _vnc,
        query: 'μαυρη οθονη',
        categoryId: 7,
      );
      final withoutCategory = KnowledgeMatcher.score(
        article: _vnc,
        query: 'μαυρη οθονη',
      );
      expect(withCategory, greaterThan(withoutCategory));
    });

    test('άσχετη κλήση δεν βαθμολογείται', () {
      expect(
        KnowledgeMatcher.score(
          article: _vnc,
          query: 'Να μπει το σύστημα διαλογής',
        ),
        0,
      );
    });

    test('κενό ερώτημα χωρίς κατηγορία δίνει μηδέν', () {
      expect(KnowledgeMatcher.score(article: _vnc, query: '   '), 0);
    });
  });

  group('rank', () {
    test('πρώτο έρχεται το πιο σχετικό, όχι το πιο χρησιμοποιημένο', () {
      final ranked = KnowledgeMatcher.rank(
        articles: const [_printer, _bigov, _vnc],
        query: 'Βλεπει μαυρη οθονη απο το πρωι',
      );
      expect(ranked.first.article.id, _vnc.id);
    });

    test('σε ισοβαθμία κερδίζει όσο έχει λύσει περισσότερα', () {
      const a = KnowledgeArticle(
        id: 10,
        symptom: 'δεν ανοιγει το προγραμμα',
        solution: 'επανεκκίνηση',
        timesUsed: 1,
      );
      const b = KnowledgeArticle(
        id: 11,
        symptom: 'δεν ανοιγει το προγραμμα',
        solution: 'επανεγκατάσταση',
        timesUsed: 12,
      );
      final ranked = KnowledgeMatcher.rank(
        articles: const [a, b],
        query: 'δεν ανοιγει το προγραμμα',
      );
      expect(ranked.first.article.id, 11);
    });

    test('τηρεί το όριο πλήθους', () {
      final ranked = KnowledgeMatcher.rank(
        articles: const [_printer, _bigov, _vnc],
        query: 'μαυρη οθονη εξαγωγη εκτυπωνει',
        limit: 2,
      );
      expect(ranked, hasLength(2));
    });

    test('καμία σχέση σημαίνει κενή λίστα, όχι τυχαία πρόταση', () {
      final ranked = KnowledgeMatcher.rank(
        articles: const [_printer, _bigov, _vnc],
        query: 'αλλαγή κωδικού πρόσβασης δικτύου',
      );
      expect(ranked, isEmpty);
    });
  });

  group('findDuplicate', () {
    test('το ίδιο σύμπτωμα με ίδια κατηγορία θεωρείται διπλό', () {
      final duplicate = KnowledgeMatcher.findDuplicate(
        articles: const [_printer, _bigov, _vnc],
        query: 'Βλέπει μαύρη οθόνη από το πρωί',
        categoryId: 7,
      );
      expect(duplicate?.id, _vnc.id);
    });

    test('χαλαρή σχέση ΔΕΝ θεωρείται διπλό — δεν σβήνει δουλεμένη λύση', () {
      // Μοιράζεται μόνο την «οθόνη»: αξίζει να προταθεί στην ΤΝ ως σχετικό,
      // αλλά είναι άλλο πρόβλημα και δεν επιτρέπεται να αντικαταστήσει το άρθρο.
      const looselyRelated = 'Η οθονη τρεμοπαιζει';

      expect(
        KnowledgeMatcher.rank(articles: const [_vnc], query: looselyRelated),
        isNotEmpty,
      );
      expect(
        KnowledgeMatcher.findDuplicate(
          articles: const [_vnc],
          query: looselyRelated,
        ),
        isNull,
      );
    });

    test('άσχετο πρόβλημα δεν βρίσκει διπλό', () {
      expect(
        KnowledgeMatcher.findDuplicate(
          articles: const [_printer, _bigov, _vnc],
          query: 'αλλαγή τόνερ στον εκτυπωτή του τρίτου ορόφου',
        ),
        isNull,
      );
    });
  });

  group('KnowledgePromptContext.format', () {
    test('χωρίς άρθρα δεν παράγει κείμενο — το block θα αφαιρεθεί', () {
      expect(KnowledgePromptContext.format(const []), isEmpty);
    });

    test('άρθρο χωρίς λύση δεν μπαίνει στην προτροπή', () {
      const incomplete = KnowledgeArticle(id: 4, symptom: 'κάτι', solution: '');
      expect(KnowledgePromptContext.format(const [incomplete]), isEmpty);
    });

    test('δίνει σύμπτωμα και λύση ανά άρθρο', () {
      final text = KnowledgePromptContext.format(const [_vnc]);
      expect(text, contains('Σύμπτωμα: Βλέπει μαύρη οθόνη από το πρωί'));
      expect(text, contains('Λύση: Η μαύρη οθόνη οφείλεται'));
    });
  });
}
