// Τι γράφεται στην ΠΕΡΙΓΡΑΦΗ της κλήσης όταν πατηθεί «Αποθήκευση στην κλήση».
//
// Το επίμαχο σημείο δεν είναι η μορφή του κειμένου αλλά **ποιος τίτλος
// κατεβαίνει και πόσες φορές**: ο τίτλος ξαναφτιάχνεται σε κάθε άνοιγμα του
// διαλόγου, ενώ η Περιγραφή ξαναδιαβάζεται αποθηκευμένη — χωρίς φρουρό, κάθε
// αποθήκευση της ίδιας κλήσης θα πρόσθετε άλλη μία φορά τον ίδιο τίτλο.
//
//   flutter test test/core/services/lansweeper_call_issue_test.dart

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/services/lansweeper_sync_service.dart';
import 'package:call_logger/features/history/widgets/lansweeper_report_call_save.dart';
import 'package:flutter_test/flutter_test.dart';

String _issue({
  required String title,
  required String autoTitle,
  required String notes,
}) => LansweeperSyncService.buildCallIssue(
  title: title,
  autoTitle: autoTitle,
  notes: notes,
);

void main() {
  group('Ο τίτλος στην περιγραφή της κλήσης', () {
    test(
      'ουσιαστικός τίτλος κατεβαίνει ως πρώτη παράγραφος, χωρίς ετικέτα',
      () {
        final result = _issue(
          title: 'Ο εκτυπωτής δεν τραβά χαρτί',
          autoTitle: 'Κλήση #344',
          notes: 'Τι θα γίνει με τη λύση;',
        );

        expect(
          result,
          'Ο εκτυπωτής δεν τραβά χαρτί\n\nΤι θα γίνει με τη λύση;',
        );
        expect(result.toLowerCase(), isNot(contains('τίτλος')));
        expect(result, startsWith('Ο εκτυπωτής'));
      },
    );

    test('ο αυτόματος τίτλος ΔΕΝ κατεβαίνει — δεν λέει τίποτα νέο', () {
      final result = _issue(
        title: 'Κλήση #344',
        autoTitle: 'Κλήση #344',
        notes: 'Τι θα γίνει με τη λύση;',
      );

      expect(result, 'Τι θα γίνει με τη λύση;');
      expect(result, isNot(contains('#344')));
    });

    test('ο αυτόματος τίτλος με κατηγορία επίσης δεν κατεβαίνει', () {
      final auto = LansweeperSyncService.autoTicketTitle(
        category: 'Εκτυπωτές',
        id: 344,
      );

      expect(auto, '[Εκτυπωτές] #344');
      expect(_issue(title: auto, autoTitle: auto, notes: 'Κάτι'), 'Κάτι');
    });

    test('δεύτερη αποθήκευση δεν ξαναγράφει τον τίτλο', () {
      const title = 'Ο εκτυπωτής δεν τραβά χαρτί';
      final first = _issue(
        title: title,
        autoTitle: 'Κλήση #344',
        notes: 'Τι θα γίνει με τη λύση;',
      );
      // Δεύτερο άνοιγμα: η Περιγραφή έρχεται από τη βάση (περιέχει ήδη τον
      // τίτλο), ενώ ο τίτλος ξαναγεννιέται ίδιος.
      final second = _issue(
        title: title,
        autoTitle: 'Κλήση #344',
        notes: first,
      );

      expect(second, first);
      expect(title.allMatches(second).length, 1);
    });

    test('κενή περιγραφή: μένει μόνο ο τίτλος, χωρίς κενές γραμμές', () {
      expect(
        _issue(title: 'Χαλασμένο πληκτρολόγιο', autoTitle: 'Κλήση', notes: ''),
        'Χαλασμένο πληκτρολόγιο',
      );
    });

    test('κενός τίτλος: η περιγραφή μένει ανέπαφη', () {
      expect(
        _issue(title: '   ', autoTitle: 'Κλήση #1', notes: 'Μόνο περιγραφή'),
        'Μόνο περιγραφή',
      );
    });
  });

  group('Πότε προσφέρεται η αποθήκευση στην κλήση', () {
    test('χωρίς επιλεγμένη κλήση δεν υπάρχει πού να γραφτεί', () {
      expect(
        LansweeperReportCallSave.disabledReasonFor(
          selectedCount: 0,
          notes: 'Κάτι',
          solution: 'Κάτι',
          hasChanges: true,
        ),
        isNotNull,
      );
    });

    test('χωρίς κανένα κείμενο δεν υπάρχει τι να σωθεί', () {
      expect(
        LansweeperReportCallSave.disabledReasonFor(
          selectedCount: 1,
          notes: '  ',
          solution: '',
          hasChanges: false,
        ),
        isNotNull,
      );
    });

    test('μόνη της η λύση αρκεί — δεν απαιτείται και περιγραφή', () {
      expect(
        LansweeperReportCallSave.disabledReasonFor(
          selectedCount: 1,
          notes: '',
          solution: 'Άλλαξα το καλώδιο',
          hasChanges: true,
        ),
        isNull,
      );
    });

    test('πολλές επιλεγμένες κλήσεις επιτρέπονται', () {
      expect(
        LansweeperReportCallSave.disabledReasonFor(
          selectedCount: 3,
          notes: 'Κάτι',
          solution: '',
          hasChanges: true,
        ),
        isNull,
      );
    });

    test('χωρίς καμία αλλαγή το κουμπί ΔΕΝ προσφέρεται', () {
      final reason = LansweeperReportCallSave.disabledReasonFor(
        selectedCount: 1,
        notes: 'Ήδη αποθηκευμένο',
        solution: 'Ήδη αποθηκευμένη λύση',
        hasChanges: false,
      );

      expect(reason, isNotNull);
      expect(reason, contains('ήδη αποθηκευμένο'));
    });
  });

  group('Τι μετράει ως αλλαγή', () {
    test('ίδια κείμενα με την κλήση: καμία αλλαγή', () {
      expect(
        CallsLansweeperRepository.wouldChangeTexts(
          problem: 'Δεν τυπώνει',
          solution: 'Άλλαξα καλώδιο',
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
        ),
        isFalse,
      );
    });

    test('τα κενά γύρω από το κείμενο δεν είναι αλλαγή', () {
      expect(
        CallsLansweeperRepository.wouldChangeTexts(
          problem: '  Δεν τυπώνει  ',
          solution: '',
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
        ),
        isFalse,
      );
    });

    test('αλλαγμένη περιγραφή μετράει', () {
      expect(
        CallsLansweeperRepository.wouldChangeTexts(
          problem: 'Δεν τυπώνει καθόλου',
          solution: 'Άλλαξα καλώδιο',
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
        ),
        isTrue,
      );
    });

    test('αλλαγμένη μόνο η λύση μετράει', () {
      expect(
        CallsLansweeperRepository.wouldChangeTexts(
          problem: 'Δεν τυπώνει',
          solution: 'Άλλαξα και τον οδηγό',
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
        ),
        isTrue,
      );
    });

    test('κενό πεδίο δεν μετράει ως αλλαγή — δεν σβήνει ό,τι υπάρχει', () {
      // Ίδιος κανόνας με την ίδια την εγγραφή: κενό δεν αδειάζει τη λύση.
      expect(
        CallsLansweeperRepository.wouldChangeTexts(
          problem: 'Δεν τυπώνει',
          solution: '',
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
        ),
        isFalse,
      );
    });

    test(
      'κλήση χωρίς κανένα αποθηκευμένο κείμενο: κάθε κείμενο είναι αλλαγή',
      () {
        expect(
          CallsLansweeperRepository.wouldChangeTexts(
            problem: 'Δεν τυπώνει',
            solution: '',
            currentIssue: null,
            currentSolution: null,
          ),
          isTrue,
        );
      },
    );

    test('δύο κενά πεδία δεν γράφουν τίποτα', () {
      expect(
        CallsLansweeperRepository.wouldChangeTexts(
          problem: '   ',
          solution: '',
          currentIssue: 'Κάτι',
          currentSolution: 'Κάτι',
        ),
        isFalse,
      );
    });
  });
}
