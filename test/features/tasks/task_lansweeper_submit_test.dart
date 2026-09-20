// Η αποστολή μιας εκκρεμότητας στο Lansweeper: με τι ανοίγει η φόρμα, τι
// φεύγει προς το API, και —κυρίως— τι ΔΕΝ αγγίζει η αποστολή.
//
//   flutter test test/features/tasks/task_lansweeper_submit_test.dart

import 'package:call_logger/core/database/tasks_lansweeper_repository.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/providers/task_lansweeper_submit_provider.dart';
import 'package:call_logger/features/tasks/services/task_lansweeper_form_seed.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task({
  int? id = 7,
  String title = 'Δεν τυπώνει ο εκτυπωτής στη Γραμματεία ΤΕΠ',
  String? description = 'Δέχεται την εντολή αλλά δεν βγάζει σελίδα.',
  String? solutionNotes,
  int? callerId = 12,
  String? userText = 'Βαρβάρα Ψαρρά',
  String? departmentText = 'Γραμματεία ΤΕΠ',
}) {
  return Task(
    id: id,
    title: title,
    description: description,
    solutionNotes: solutionNotes,
    callerId: callerId,
    userText: userText,
    departmentText: departmentText,
    dueDate: '2026-09-21T14:30:00.000',
    status: 'open',
  );
}

void main() {
  group('με τι ανοίγει η φόρμα', () {
    test('κάθε πεδίο πάει στη θέση του, ένα προς ένα', () {
      final seed = seedLansweeperFormFromTask(
        _task(solutionNotes: 'Αλλαγή προγράμματος οδήγησης.'),
      );

      expect(seed.title, 'Δεν τυπώνει ο εκτυπωτής στη Γραμματεία ΤΕΠ');
      expect(seed.problem, 'Δέχεται την εντολή αλλά δεν βγάζει σελίδα.');
      expect(seed.solution, 'Αλλαγή προγράμματος οδήγησης.');
    });

    test('εκκρεμότητα χωρίς λύση ανοίγει με κενό πεδίο, όχι με null', () {
      final seed = seedLansweeperFormFromTask(_task());

      expect(seed.solution, isEmpty);
    });

    test('τίτλος που έμεινε κενός δεν αφήνει το αίτημα χωρίς θέμα', () {
      final seed = seedLansweeperFormFromTask(_task(title: '   '));

      expect(seed.title, 'Εκκρεμότητα #7');
    });
  });

  group('ποιο πρόσωπο εκπροσωπεί η εκκρεμότητα', () {
    test('ο υπάλληλος και το τμήμα του περνούν στην ιεραρχία', () {
      final party = requesterPartyForTask(_task());

      expect(party.personId, 12);
      expect(party.personLabel, 'Βαρβάρα Ψαρρά');
      expect(party.departmentText, 'Γραμματεία ΤΕΠ');
    });

    test('χωρίς όνομα, ο υπάλληλος αναγνωρίζεται από τον αριθμό του', () {
      final party = requesterPartyForTask(_task(userText: '  '));

      expect(party.personLabel, 'Υπάλληλος #12');
    });

    test('εκκρεμότητα χωρίς συνδεδεμένο πρόσωπο δεν επινοεί κανένα', () {
      final party = requesterPartyForTask(
        _task(callerId: null, userText: null),
      );

      expect(party.personId, isNull);
    });
  });

  group('πότε έχει νόημα η αποθήκευση στην εκκρεμότητα', () {
    test('ίδιο κείμενο με το αποθηκευμένο δεν αλλάζει τίποτα', () {
      final task = _task(solutionNotes: 'Αλλαγή οδηγού.');

      expect(
        TasksLansweeperRepository.wouldChangeTexts(
          title: task.title,
          problem: task.description!,
          solution: task.solutionNotes!,
          current: task,
        ),
        isFalse,
      );
    });

    test('αλλαγή έστω σε ένα πεδίο αρκεί', () {
      final task = _task();

      expect(
        TasksLansweeperRepository.wouldChangeTexts(
          title: task.title,
          problem: 'Νέα, καθαρότερη περιγραφή.',
          solution: '',
          current: task,
        ),
        isTrue,
      );
    });

    test('κενά πεδία δεν σβήνουν ό,τι υπάρχει', () {
      final task = _task(solutionNotes: 'Αλλαγή οδηγού.');

      expect(
        TasksLansweeperRepository.wouldChangeTexts(
          title: '',
          problem: '',
          solution: '',
          current: task,
        ),
        isFalse,
        reason: 'άδεια φόρμα δεν είναι εντολή διαγραφής',
      );
    });
  });
}
