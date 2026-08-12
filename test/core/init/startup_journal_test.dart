import 'package:call_logger/core/init/startup_journal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StartupJournal journal;

  setUp(() {
    journal = StartupJournal.instance..reset();
  });

  group('Ημερολόγιο εκκίνησης', () {
    test('το βήμα που ξεκινά φαίνεται αμέσως ως «τρέχει»', () {
      journal.begin('Έλεγχος διαδρομής βάσης');

      expect(journal.steps.value, hasLength(1));
      expect(journal.steps.value.single.label, 'Έλεγχος διαδρομής βάσης');
      expect(journal.steps.value.single.status, StartupStepStatus.running);
      expect(journal.steps.value.single.duration, isNull);
    });

    test('το κλείσιμο σφραγίζει έκβαση και διάρκεια', () {
      journal.begin('Άνοιγμα βάσης δεδομένων').ok();

      final step = journal.steps.value.single;
      expect(step.status, StartupStepStatus.ok);
      expect(step.duration, isNotNull);
    });

    test('η λαβή αλλάζει κείμενο χωρίς να κλείσει το βήμα', () {
      final step = journal.begin('Άνοιγμα βάσης σε 5 δευτερόλεπτα');
      step.relabel('Άνοιγμα βάσης σε 4 δευτερόλεπτα');

      expect(
        journal.steps.value.single.label,
        'Άνοιγμα βάσης σε 4 δευτερόλεπτα',
      );
      expect(journal.steps.value.single.status, StartupStepStatus.running);
      expect(journal.steps.value, hasLength(1));
    });

    test('δεύτερο κλείσιμο της ίδιας λαβής αγνοείται', () {
      final step = journal.begin('Έλεγχος υγείας βάσης');
      step.ok();
      step.fail('δεν πρέπει να περάσει');

      expect(journal.steps.value.single.status, StartupStepStatus.ok);
      expect(journal.steps.value.single.detail, isNull);
    });

    test('η προειδοποίηση κρατά τη λεπτομέρεια', () {
      journal.begin('Έλεγχος αντιγράφων ασφαλείας').warn('Άφταστος φάκελος');

      final step = journal.steps.value.single;
      expect(step.status, StartupStepStatus.warning);
      expect(step.detail, 'Άφταστος φάκελος');
    });

    test('τα βήματα χωρίς δουλειά δεν φτάνουν στην οθόνη', () {
      journal.begin('Καθαρισμός υπολειμμάτων ενημέρωσης').skip();
      journal.begin('Έλεγχος υγείας βάσης').ok();

      expect(journal.steps.value, hasLength(2));
      expect(journal.visibleSteps, hasLength(1));
      expect(journal.visibleSteps.single.label, 'Έλεγχος υγείας βάσης');
    });

    test('η αποτυχία γίνεται ορατή στο hasFailure', () {
      expect(journal.hasFailure, isFalse);

      journal.begin('Άνοιγμα βάσης δεδομένων').fail('database is locked');

      expect(journal.hasFailure, isTrue);
    });

    test('κάθε μεταβολή ειδοποιεί τους ακροατές', () {
      var notifications = 0;
      void listener() => notifications++;
      journal.steps.addListener(listener);
      addTearDown(() => journal.steps.removeListener(listener));

      final step = journal.begin('Φόρτωση μηχανής SQLite');
      expect(notifications, 1);

      step.relabel('Φόρτωση μηχανής SQLite (2η προσπάθεια)');
      expect(notifications, 2);

      step.ok();
      expect(notifications, 3);
    });

    test('το reset αδειάζει το ημερολόγιο', () {
      journal.begin('Έλεγχος διαδρομής βάσης').ok();
      journal.begin('Έλεγχος υγείας βάσης').ok();

      journal.reset();

      expect(journal.steps.value, isEmpty);
      expect(journal.hasFailure, isFalse);
    });

    test('λαβή που έμεινε ανοιχτή μετά το reset δεν ξαναγράφει', () {
      final orphan = journal.begin('Ξεχασμένο βήμα');
      journal.reset();

      orphan.ok();

      expect(journal.steps.value, isEmpty);
    });
  });

  group('Προοίμιο εκκίνησης', () {
    test('η επαναδοκιμή κρατά το προοίμιο και σβήνει τα υπόλοιπα', () {
      journal.begin('Φόρτωση μηχανής SQLite').ok();
      journal.begin('Προετοιμασία παραθύρου').ok();
      journal.sealBootPrefix();

      journal.begin('Έλεγχος διαδρομής βάσης').ok();
      journal.begin('Άνοιγμα βάσης δεδομένων').fail('database is locked');

      journal.rewindToBootPrefix();

      expect(
        journal.steps.value.map((s) => s.label),
        ['Φόρτωση μηχανής SQLite', 'Προετοιμασία παραθύρου'],
      );
      expect(journal.hasFailure, isFalse);
    });

    test('τρεις επαναδοκιμές δεν αφήνουν τρία αντίγραφα', () {
      journal.begin('Προετοιμασία παραθύρου').ok();
      journal.sealBootPrefix();

      for (var attempt = 0; attempt < 3; attempt++) {
        journal.rewindToBootPrefix();
        journal.begin('Έλεγχος διαδρομής βάσης').ok();
        journal.begin('Άνοιγμα βάσης δεδομένων').ok();
      }

      expect(journal.steps.value, hasLength(3));
      expect(journal.steps.value.first.label, 'Προετοιμασία παραθύρου');
    });

    test('χωρίς σφράγιση, η επαναδοκιμή αδειάζει τα πάντα', () {
      journal.begin('Έλεγχος διαδρομής βάσης').ok();

      journal.rewindToBootPrefix();

      expect(journal.steps.value, isEmpty);
    });

    test('το rewind δεν πειράζει ημερολόγιο που είναι ήδη στο προοίμιο', () {
      journal.begin('Προετοιμασία παραθύρου').ok();
      journal.sealBootPrefix();

      journal.rewindToBootPrefix();
      journal.rewindToBootPrefix();

      expect(journal.steps.value, hasLength(1));
    });
  });

  group('runStep', () {
    test('επιτυχία: κλείνει το βήμα και επιστρέφει την τιμή', () async {
      final result = await journal.runStep(
        'Φόρτωση λεξικού ορθογραφίας',
        () async => 42,
      );

      expect(result, 42);
      expect(journal.steps.value.single.status, StartupStepStatus.ok);
    });

    test('αποτυχία: γίνεται προειδοποίηση, δεν ξαναπετιέται', () async {
      final result = await journal.runStep<int>(
        'Εκκαθάριση ιστορικού ελέγχου',
        () async => throw StateError('η βάση δεν απάντησε'),
      );

      expect(result, isNull);
      final step = journal.steps.value.single;
      expect(step.status, StartupStepStatus.warning);
      expect(step.detail, contains('η βάση δεν απάντησε'));
    });

    test('μια αποτυχία δεν σταματά τα επόμενα βήματα', () async {
      await journal.runStep<void>(
        'Μεταφορά ορόφων τμημάτων',
        () async => throw Exception('σκάει'),
      );
      await journal.runStep('Επαναφορά παραθύρου', () async => true);

      expect(journal.steps.value, hasLength(2));
      expect(journal.steps.value.first.status, StartupStepStatus.warning);
      expect(journal.steps.value.last.status, StartupStepStatus.ok);
      expect(journal.hasFailure, isFalse);
    });
  });
}
