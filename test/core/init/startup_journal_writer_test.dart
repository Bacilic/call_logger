import 'package:call_logger/core/init/startup_journal.dart';
import 'package:call_logger/core/init/startup_journal_writer.dart';
import 'package:call_logger/core/services/log_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StartupJournal journal;
  late List<LogRecord> sink;
  late StartupJournalWriter writer;

  setUp(() {
    journal = StartupJournal.instance..reset();
    sink = [];
    writer = StartupJournalWriter(
      append: sink.add,
      appVersion: '1.0.0',
      journal: journal,
      now: () => DateTime(2026, 9, 15, 8, 12, 33),
    );
  });

  tearDown(() {
    writer.detach();
    journal.reset();
  });

  /// Πόσες εγγραφές αναφέρουν το κείμενο, στο μήνυμα ή στη λεπτομέρεια.
  int occurrences(String needle) => sink
      .where(
        (record) =>
            record.message.contains(needle) ||
            (record.details ?? '').contains(needle),
      )
      .length;

  /// Η εγγραφή του βήματος με αυτή την ετικέτα.
  LogRecord stepRecord(String label) =>
      sink.singleWhere((record) => record.message == label);

  Iterable<LogRecord> phase(String name) =>
      sink.where((record) => record.data['phase'] == name);

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
      expect(stepRecord('Άνοιγμα βάσης δεδομένων').data['status'], 'ok');
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
          'αρχείο κρατά μία εγγραφή, την τελική',
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
        sink.first.data['phase'],
        'begin',
        reason: greekExpectMsg('Η αρχή της εκκίνησης ανοίγει το μπλοκ'),
      );
      expect(sink.first.message, contains('ΕΚΚΙΝΗΣΗ v1.0.0'));
    });

    test('κάθε εγγραφή είναι εγγραφή εκκίνησης', () {
      writer.attach();
      journal.begin('Πρώτο').ok();
      writer.sealAttempt(success: true);

      expect(
        sink.map((record) => record.kind).toSet(),
        {LogKind.startup},
        reason: greekExpectMsg(
          'Η εξαγωγή μετρά τις εκκινήσεις από το είδος, όχι από λέξεις',
        ),
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
      expect(stepRecord('Μεταφορά ορόφων τμημάτων').data['status'], 'skipped');
    });

    test('η προειδοποίηση κουβαλά την αιτία της', () {
      writer.attach();
      journal.begin('Έλεγχος ενημέρωσης').warn('το δίκτυο δεν απάντησε');

      final record = stepRecord('Έλεγχος ενημέρωσης');
      expect(record.severity, LogSeverity.warning);
      expect(record.details, 'το δίκτυο δεν απάντησε');
    });

    test('η πολύγραμμη αιτία ισοπεδώνεται σε μία γραμμή', () {
      writer.attach();
      journal
          .begin('Άνοιγμα βάσης')
          .fail('πρώτη γραμμή\nδεύτερη γραμμή\n   τρίτη');

      expect(
        stepRecord('Άνοιγμα βάσης').details,
        'πρώτη γραμμή δεύτερη γραμμή τρίτη',
      );
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
        expect(phase('retry'), hasLength(1));
      },
    );

    test('νέα αρχικοποίηση μετά από ΕΠΙΤΥΧΙΑ είναι αλλαγή βάσης, όχι '
        'νέα προσπάθεια', () {
      journal.sealBootPrefix();
      writer.attach();
      journal.begin('Άνοιγμα βάσης δεδομένων').ok();
      writer.sealAttempt(success: true);

      journal.rewindToBootPrefix();
      writer.beginAttempt();

      expect(
        phase('retry'),
        isEmpty,
        reason: greekExpectMsg(
          'Η πρώτη αρχικοποίηση πέτυχε — η δεύτερη δεν είναι επανάληψη',
        ),
      );
      expect(phase('reinit'), hasLength(1));
    });

    test('η πρώτη προσπάθεια ΔΕΝ γράφει «νέα προσπάθεια»', () {
      journal.sealBootPrefix();
      writer.attach();
      journal.rewindToBootPrefix();
      writer.beginAttempt();

      expect(phase('retry'), isEmpty);
    });

    test('βήμα που δεν έκλεισε ποτέ γράφεται ρητά ως ημιτελές', () {
      writer.attach();
      journal.begin('Άνοιγμα βάσης δεδομένων');
      writer.sealAttempt(success: false);

      expect(occurrences('Άνοιγμα βάσης δεδομένων'), 1);
      expect(
        stepRecord('Άνοιγμα βάσης δεδομένων').data['status'],
        'unfinished',
      );
    });

    test('το κλείσιμο αναφέρει έκβαση και άθροισμα των βημάτων', () {
      writer.attach();
      journal.begin('Πρώτο').ok();
      journal.note('Δεύτερο');
      writer.sealAttempt(success: true);

      final end = phase('end').single;
      expect(end.data['success'], isTrue);
      expect(end.data['total_ms'], isA<int>());
      expect(end.message, contains('σύνολο βημάτων'));
    });

    test('μετά το ξήλωμα ο γραφέας δεν ακούει πια το ημερολόγιο', () {
      writer.attach();
      writer.detach();
      journal.begin('Άνοιγμα βάσης δεδομένων').ok();

      expect(occurrences('Άνοιγμα βάσης δεδομένων'), 0);
    });
  });
}
