// Η γέφυρα κειμένου κλήσης ↔ εκκρεμότητας.
//
//   flutter test test/features/tasks/call_task_solution_bridge_test.dart

import 'package:call_logger/features/tasks/services/call_task_solution_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Κλήση → σημειώσεις εκκρεμότητας', () {
    test('η λύση της κλήσης ακολουθεί, με ένδειξη', () {
      final notes = taskNotesFromCall(
        notes: 'Δεν μπορώ να τιμολογήσω',
        solution: 'Να γίνει αίτημα στην DataMed',
      );

      expect(
        notes,
        'Δεν μπορώ να τιμολογήσω\n\nΛύση: Να γίνει αίτημα στην DataMed',
      );
    });

    test('χωρίς λύση δεν μένει ούτε ετικέτα ούτε κενές γραμμές', () {
      expect(
        taskNotesFromCall(notes: 'Δεν μπορώ να τιμολογήσω', solution: '   '),
        'Δεν μπορώ να τιμολογήσω',
      );
    });

    test('λύση χωρίς περιγραφή στέκει μόνη της', () {
      expect(
        taskNotesFromCall(notes: '', solution: 'Να γίνει αίτημα'),
        'Λύση: Να γίνει αίτημα',
      );
    });
  });

  group('Εκκρεμότητα → λύση κλήσης', () {
    test('η τελική λύση προστίθεται· τα πρώτα βήματα μένουν', () {
      // Η αλυσίδα «από πού ξεκίνησε → πώς έκλεισε» δεν σβήνεται ποτέ.
      final next = callSolutionAfterTaskClose(
        existingCallSolution: 'Να γίνει αίτημα στην DataMed',
        taskSolution: 'Η DataMed δημιούργησε μηχανισμό τιμολογίων',
      );

      expect(
        next,
        'Να γίνει αίτημα στην DataMed\n\n'
        'Από την εκκρεμότητα: Η DataMed δημιούργησε μηχανισμό τιμολογίων',
      );
    });

    test('άδεια λύση κλήσης παίρνει μόνο τη νέα', () {
      final next = callSolutionAfterTaskClose(
        existingCallSolution: null,
        taskSolution: 'Η DataMed δημιούργησε μηχανισμό τιμολογίων',
      );

      expect(
        next,
        'Από την εκκρεμότητα: Η DataMed δημιούργησε μηχανισμό τιμολογίων',
      );
    });

    test('το ξανακλείσιμο δεν διπλογράφει', () {
      final next = callSolutionAfterTaskClose(
        existingCallSolution:
            'Να γίνει αίτημα στην DataMed\n\n'
            'Από την εκκρεμότητα: Η DataMed δημιούργησε μηχανισμό τιμολογίων',
        taskSolution: 'Η DataMed δημιούργησε μηχανισμό τιμολογίων',
      );

      expect(next, isNull);
    });

    test('κλείσιμο χωρίς λύση δεν αγγίζει την κλήση', () {
      expect(
        callSolutionAfterTaskClose(
          existingCallSolution: 'Να γίνει αίτημα στην DataMed',
          taskSolution: '   ',
        ),
        isNull,
      );
    });
  });
}
