import 'package:call_logger/core/init/startup_journal.dart';
import 'package:call_logger/core/init/startup_journal_writer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StartupJournal journal;
  late StringBuffer sink;
  late StartupJournalWriter writer;

  setUp(() {
    journal = StartupJournal.instance..reset();
    sink = StringBuffer();
    writer = StartupJournalWriter(
      append: sink.write,
      appVersion: '1.0.0',
      journal: journal,
      now: () => DateTime(2026, 9, 15, 8, 12, 33),
    );
  });

  tearDown(() {
    writer.detach();
    journal.reset();
  });

  /// Πόσες φορές εμφανίζεται το κείμενο στο αρχείο.
  int occurrences(String needle) => needle.allMatches(sink.toString()).length;

  group('StartupJournalWriter · τι φτάνει στο αρχείο', () {
    test('το βήμα γράφεται μόλις κλείσει, όχι όσο τρέχει', () {
      writer.attach();
      final step = journal.begin('Άνοιγμα βάσης δεδομένων');

      expect(
        occurrences('Άνοιγμα βάσης δεδομένων'),
        0,
        reason: greekExpectMsg('Βήμα που τρέχει δεν έχει ακόμη έκβαση'),
      );

      step.ok();
      expect(occurrences('Άνοιγμα βάσης δεδομένων'), 1);
      expect(sink.toString(), contains('ΕΝΤΑΞΕΙ'));
    });

    test('η αλλαγή κειμένου σε βήμα που τρέχει ΔΕΝ γεννά εγγραφές', () {
      writer.attach();
      final step = journal.begin('Επανασύνδεση σε 5');
      for (var left = 4; left >= 1; left--) {
        step.relabel('Επανασύνδεση σε $left');
      }
      step.ok('Επανασύνδεση');

      expect(
        occurrences('Επανασύνδεση'),
        1,
        reason: greekExpectMsg(
          'Η αντίστροφη μέτρηση αλλάζει το ίδιο βήμα δεκάδες φορές — το '
          'αρχείο κρατά μία γραμμή, την τελική',
        ),
      );
    });

    test('όσα έκλεισαν πριν συνδεθεί ο γραφέας γράφονται αναδρομικά', () {
      journal.begin('Φόρτωση μηχανής SQLite').ok();
      journal.begin('Προετοιμασία παραθύρου').ok();

      writer.attach();

      expect(occurrences('Φόρτωση μηχανής SQLite'), 1);
      expect(occurrences('Προετοιμασία παραθύρου'), 1);
      expect(
        sink.toString(),
        contains('ΕΚΚΙΝΗΣΗ v1.0.0'),
        reason: greekExpectMsg('Η κεφαλίδα ανοίγει το μπλοκ της συνεδρίας'),
      );
    });

    test('οι παραλείψεις γράφονται, σε αντίθεση με την οθόνη', () {
      writer.attach();
      journal.begin('Μεταφορά ορόφων τμημάτων').skip();

      expect(
        journal.visibleSteps,
        isEmpty,
        reason: greekExpectMsg('Η οθόνη κρύβει τις παραλείψεις'),
      );
      expect(
        occurrences('Μεταφορά ορόφων τμημάτων'),
        1,
        reason: greekExpectMsg(
          'Το αρχείο τις κρατά — απαντούν στο «γιατί δεν έγινε;»',
        ),
      );
      expect(sink.toString(), contains('ΠΑΡΑΛΕΙΨΗ'));
    });

    test('η προειδοποίηση κουβαλά την αιτία της', () {
      writer.attach();
      journal.begin('Έλεγχος ενημέρωσης').warn('το δίκτυο δεν απάντησε');

      expect(sink.toString(), contains('ΠΡΟΕΙΔΟΠ.'));
      expect(sink.toString(), contains('το δίκτυο δεν απάντησε'));
    });

    test('η πολύγραμμη αιτία ισοπεδώνεται σε μία γραμμή', () {
      writer.attach();
      journal
          .begin('Άνοιγμα βάσης')
          .fail('πρώτη γραμμή\nδεύτερη γραμμή\n   τρίτη');

      final detailLines = sink
          .toString()
          .split('\n')
          .where((line) => line.contains('πρώτη γραμμή'))
          .toList();
      expect(detailLines, hasLength(1));
      expect(detailLines.single, contains('τρίτη'));
    });

    test(
      'δεύτερη προσπάθεια: δηλώνεται ρητά και δεν διπλογράφει το προοίμιο',
      () {
        journal.begin('Φόρτωση μηχανής SQLite').ok();
        journal.sealBootPrefix();
        writer.attach();

        journal.begin('Άνοιγμα βάσης δεδομένων').fail('δεν απαντά');
        writer.sealAttempt(success: false);

        journal.rewindToBootPrefix();
        writer.beginAttempt();
        journal.begin('Άνοιγμα βάσης δεδομένων').ok();
        writer.sealAttempt(success: true);

        expect(
          occurrences('Φόρτωση μηχανής SQLite'),
          1,
          reason: greekExpectMsg(
            'Το προοίμιο έγινε μία φορά — γράφεται μία φορά',
          ),
        );
        expect(occurrences('Άνοιγμα βάσης δεδομένων'), 2);
        expect(occurrences('νέα προσπάθεια'), 1);
      },
    );

    test('η πρώτη προσπάθεια ΔΕΝ γράφει «νέα προσπάθεια»', () {
      journal.sealBootPrefix();
      writer.attach();
      journal.rewindToBootPrefix();
      writer.beginAttempt();

      expect(occurrences('νέα προσπάθεια'), 0);
    });

    test('βήμα που δεν έκλεισε ποτέ γράφεται ρητά ως ημιτελές', () {
      writer.attach();
      journal.begin('Άνοιγμα βάσης δεδομένων');
      writer.sealAttempt(success: false);

      expect(sink.toString(), contains('ΗΜΙΤΕΛΕΣ'));
      expect(occurrences('Άνοιγμα βάσης δεδομένων'), 1);
    });

    test('το κλείσιμο αναφέρει το άθροισμα των βημάτων', () {
      writer.attach();
      journal.begin('Πρώτο').ok();
      journal.note('Δεύτερο');
      writer.sealAttempt(success: true);

      expect(sink.toString(), contains('ΕΤΟΙΜΗ'));
      expect(sink.toString(), contains('σύνολο βημάτων'));
    });

    test('μετά το ξήλωμα ο γραφέας δεν ακούει πια το ημερολόγιο', () {
      writer.attach();
      writer.detach();
      journal.begin('Άνοιγμα βάσης δεδομένων').ok();

      expect(occurrences('Άνοιγμα βάσης δεδομένων'), 0);
    });
  });
}
