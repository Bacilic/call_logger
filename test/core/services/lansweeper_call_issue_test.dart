// Τι κρατά η κλήση από τη φόρμα του Lansweeper όταν πατηθεί μία από τις
// εξόδους της.
//
// Το επίμαχο σημείο είναι **ποιος τίτλος αξίζει να κρατηθεί**: το πεδίο
// προσυμπληρώνεται σε κάθε άνοιγμα με τον αυτόματο «[Κατηγορία] #id», που δεν
// είναι περίληψη — αν σωζόταν, το πρόσφατο ιστορικό θα γέμιζε με την ίδια
// φράση τρεις φορές στη σειρά.
//
//   flutter test test/core/services/lansweeper_call_issue_test.dart

import 'package:call_logger/core/database/calls_lansweeper_repository.dart';
import 'package:call_logger/core/services/lansweeper_sync_service.dart';
import 'package:call_logger/features/history/widgets/lansweeper_report_call_save.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ποιος τίτλος αξίζει να κρατηθεί στην κλήση', () {
    test('ουσιαστικός τίτλος κρατιέται αυτούσιος', () {
      expect(
        LansweeperSyncService.callTitleToPersist(
          title: 'Δυσκολία ανεύρεσης αναφοράς για κάγκελα',
          autoTitle: '[Medico] #344',
        ),
        'Δυσκολία ανεύρεσης αναφοράς για κάγκελα',
      );
    });

    test('ο αυτόματος τίτλος ΔΕΝ κρατιέται — δεν λέει τίποτα νέο', () {
      expect(
        LansweeperSyncService.callTitleToPersist(
          title: '[Medico] #344',
          autoTitle: '[Medico] #344',
        ),
        isNull,
      );
    });

    test('ο αυτόματος χωρίς κατηγορία επίσης δεν κρατιέται', () {
      expect(
        LansweeperSyncService.callTitleToPersist(
          title: 'Κλήση #12',
          autoTitle: 'Κλήση #12',
        ),
        isNull,
      );
    });

    test('κενός τίτλος δίνει null, όχι κενό κείμενο', () {
      expect(
        LansweeperSyncService.callTitleToPersist(
          title: '   ',
          autoTitle: '[Medico] #344',
        ),
        isNull,
      );
    });

    test('τα κενά γύρω από τον τίτλο κόβονται', () {
      expect(
        LansweeperSyncService.callTitleToPersist(
          title: '  Δεν τυπώνει  ',
          autoTitle: '',
        ),
        'Δεν τυπώνει',
      );
    });

    test('ο αυτόματος αναγνωρίζεται και με κενά γύρω του', () {
      expect(
        LansweeperSyncService.callTitleToPersist(
          title: '[Medico] #344',
          autoTitle: '  [Medico] #344  ',
        ),
        isNull,
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
          title: null,
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
          currentTitle: null,
        ),
        isFalse,
      );
    });

    test('τα κενά γύρω από το κείμενο δεν είναι αλλαγή', () {
      expect(
        CallsLansweeperRepository.wouldChangeTexts(
          problem: '  Δεν τυπώνει  ',
          solution: '',
          title: null,
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
          currentTitle: null,
        ),
        isFalse,
      );
    });

    test('αλλαγμένη περιγραφή μετράει', () {
      expect(
        CallsLansweeperRepository.wouldChangeTexts(
          problem: 'Δεν τυπώνει καθόλου',
          solution: 'Άλλαξα καλώδιο',
          title: null,
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
          currentTitle: null,
        ),
        isTrue,
      );
    });

    test('αλλαγμένη μόνο η λύση μετράει', () {
      expect(
        CallsLansweeperRepository.wouldChangeTexts(
          problem: 'Δεν τυπώνει',
          solution: 'Άλλαξα και τον οδηγό',
          title: null,
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
          currentTitle: null,
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
          title: null,
          currentIssue: 'Δεν τυπώνει',
          currentSolution: 'Άλλαξα καλώδιο',
          currentTitle: null,
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
            title: null,
            currentIssue: null,
            currentSolution: null,
            currentTitle: null,
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
          title: null,
          currentIssue: 'Κάτι',
          currentSolution: 'Κάτι',
          currentTitle: null,
        ),
        isFalse,
      );
    });
  });
}
