// Πώς αποφασίζεται η προέλευση του καθαρού κειμένου και πώς παρουσιάζεται.
//
//   flutter test test/features/history/call_refined_source_test.dart

import 'package:call_logger/features/calls/models/call_refined_source.dart';
import 'package:call_logger/features/history/widgets/call_refined_text_section.dart';
import 'package:call_logger/features/history/widgets/lansweeper/lansweeper_ai_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LansweeperAiPresenter.refinedSource', () {
    test('χωρίς πρόταση ΤΝ το κείμενο είναι χειρόγραφο', () {
      expect(
        LansweeperAiPresenter.refinedSource(
          aiProblem: null,
          aiSolution: null,
          problem: 'Το τμήμα αναφέρει μαύρη οθόνη.',
          solution: 'Αποσύνδεση χρήστη VNC.',
        ),
        CallRefinedSource.manual,
      );
    });

    test('πρόταση ΤΝ που στάλθηκε ως έχει', () {
      expect(
        LansweeperAiPresenter.refinedSource(
          aiProblem: 'Μαύρη οθόνη στον 5151.',
          aiSolution: 'Αποσύνδεση συνεδρίας VNC.',
          problem: 'Μαύρη οθόνη στον 5151.',
          solution: 'Αποσύνδεση συνεδρίας VNC.',
        ),
        CallRefinedSource.ai,
      );
    });

    test('κενά γύρω από το κείμενο δεν το κάνουν επεξεργασμένο', () {
      expect(
        LansweeperAiPresenter.refinedSource(
          aiProblem: 'Μαύρη οθόνη στον 5151.',
          aiSolution: 'Αποσύνδεση συνεδρίας VNC.',
          problem: '  Μαύρη οθόνη στον 5151.  ',
          solution: 'Αποσύνδεση συνεδρίας VNC.\n',
        ),
        CallRefinedSource.ai,
      );
    });

    test('αλλαγή στη λύση μόνο αρκεί για «επεξεργασμένο»', () {
      expect(
        LansweeperAiPresenter.refinedSource(
          aiProblem: 'Μαύρη οθόνη στον 5151.',
          aiSolution: 'Επανεκκίνηση υπολογιστή.',
          problem: 'Μαύρη οθόνη στον 5151.',
          solution: 'Αποσύνδεση συνεδρίας VNC.',
        ),
        CallRefinedSource.aiEdited,
      );
    });
  });

  group('CallRefinedTextSection.provenanceLabel', () {
    test('προέλευση και στιγμή μαζί', () {
      expect(
        CallRefinedTextSection.provenanceLabel(
          source: CallRefinedSource.aiEdited,
          refinedAt: '2026-07-15T13:24:00',
        ),
        'από ΤΝ · επεξεργασμένο · 15/07 13:24',
      );
    });

    test('χωρίς χρονοσφραγίδα μένει μόνο η προέλευση', () {
      expect(
        CallRefinedTextSection.provenanceLabel(
          source: CallRefinedSource.ai,
          refinedAt: null,
        ),
        'από ΤΝ',
      );
    });

    test('άγνωστη προέλευση χωρίς στιγμή δεν εμφανίζει τίποτα', () {
      expect(
        CallRefinedTextSection.provenanceLabel(source: null, refinedAt: null),
        isEmpty,
      );
    });
  });
}
