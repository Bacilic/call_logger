// Πότε επιτρέπεται το «Αποθήκευση ως γνώση».
//
// Το άρθρο περιγράφει ΕΙΔΟΣ βλάβης και κρατά ΜΙΑ κλήση προέλευσης — γι' αυτό
// δουλεύει μόνο με μία επιλεγμένη κλήση. Σύμπτωμα και λύση διαβάζονται από τα
// πεδία της φόρμας, ώστε ό,τι μόλις διόρθωσε ο χρήστης να είναι αυτό που
// αποθηκεύεται. Ο τίτλος ΔΕΝ είναι προϋπόθεση: το άρθρο τον παράγει από το
// σύμπτωμα όταν λείπει (βλ. KnowledgeArticleDraft.fromCall).
//
//   flutter test test/features/history/lansweeper_report_knowledge_gate_test.dart

import 'package:call_logger/features/history/widgets/lansweeper_report_knowledge.dart';
import 'package:flutter_test/flutter_test.dart';

const _kSymptom = 'δεν εκτυπωνει';
const _kSolution = 'επανεκκίνηση εκτυπωτή';

void main() {
  group('LansweeperReportKnowledge.disabledReasonFor', () {
    test('χωρίς επιλογή ζητά πρώτα κλήση', () {
      expect(
        LansweeperReportKnowledge.disabledReasonFor(
          selectedCount: 0,
          symptom: _kSymptom,
          solution: _kSolution,
        ),
        contains('Επιλέξτε'),
      );
    });

    test('πολλές κλήσεις: το άρθρο δεν είναι συλλογή περιστατικών', () {
      final reason = LansweeperReportKnowledge.disabledReasonFor(
        selectedCount: 3,
        symptom: _kSymptom,
        solution: _kSolution,
      );

      expect(reason, isNotNull);
      expect(reason, contains('μία'));
    });

    test('κενή λύση μπλοκάρει', () {
      expect(
        LansweeperReportKnowledge.disabledReasonFor(
          selectedCount: 1,
          symptom: _kSymptom,
          solution: '   ',
        ),
        contains('Λύση'),
      );
    });

    test('κενό σύμπτωμα μπλοκάρει', () {
      expect(
        LansweeperReportKnowledge.disabledReasonFor(
          selectedCount: 1,
          symptom: '  ',
          solution: _kSolution,
        ),
        isNotNull,
      );
    });

    test('μία κλήση με σύμπτωμα και λύση: επιτρέπεται', () {
      expect(
        LansweeperReportKnowledge.disabledReasonFor(
          selectedCount: 1,
          symptom: _kSymptom,
          solution: _kSolution,
        ),
        isNull,
      );
    });

    test('χειρόγραφη λύση χωρίς καμία ΤΝ επιτρέπεται το ίδιο', () {
      expect(
        LansweeperReportKnowledge.disabledReasonFor(
          selectedCount: 1,
          symptom: 'δεν ανοιγει το medico',
          solution: 'καθαρισμος cache και επανεκκινηση',
        ),
        isNull,
      );
    });
  });
}
