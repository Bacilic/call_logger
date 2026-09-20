// Τι γράφεται στο φύλλο μιας εκκρεμότητας — και, κυρίως, τι ΔΕΝ γράφεται.
//
//   flutter test test/features/tasks/task_print_document_test.dart

import 'dart:convert';

import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/services/task_print_document.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task({
  int? id = 204,
  String title = 'Λίστα χειρουργείων και Εξιτήρια για Γρ. Κίνησης',
  String? description = 'να αυξηθεί ο αριθμός εξητήριων.',
  String? solutionNotes,
  String? userText = 'Θάνια Αναγνωστοπούλου',
  String? departmentText = 'Γραμματεία Κίνησης',
  String? phoneText = '2531',
  String? equipmentText,
  int? callId,
  String? lansweeperMainTicketId,
  String? snoozeHistoryJson,
  String? completedAt,
  String status = 'open',
}) {
  return Task(
    id: id,
    title: title,
    description: description,
    solutionNotes: solutionNotes,
    userText: userText,
    departmentText: departmentText,
    phoneText: phoneText,
    equipmentText: equipmentText,
    callId: callId,
    lansweeperMainTicketId: lansweeperMainTicketId,
    snoozeHistoryJson: snoozeHistoryJson,
    completedAt: completedAt,
    createdAt: '2026-09-02T10:34:21.000',
    dueDate: '2026-09-02T11:32:12.000',
    status: status,
  );
}

void main() {
  group('η ταυτότητα του φύλλου', () {
    test('ο αριθμός είναι εκεί — είναι ο μόνος τρόπος να ξαναβρεθεί', () {
      final doc = buildTaskPrintDocument(_task());

      expect(doc.heading, 'Εκκρεμότητα #204');
      expect(doc.createdAtLabel, '02/09/2026 10:34');
      expect(doc.dueLabel, 'Προθεσμία: 02/09/2026 11:32');
    });

    test('τίτλος που έμεινε κενός δεν αφήνει το φύλλο ανώνυμο', () {
      expect(buildTaskPrintDocument(_task(title: '  ')).title, 'Χωρίς τίτλο');
    });

    test('το όνομα αρχείου κουβαλά τον αριθμό', () {
      expect(taskPrintFileName(_task()), 'εκκρεμότητα-204.pdf');
    });
  });

  group('τα στοιχεία της δουλειάς', () {
    test('ποιος, πού και τηλέφωνο — με το τηλέφωνο τονισμένο', () {
      final doc = buildTaskPrintDocument(_task());

      expect(doc.fields.map((f) => f.label), ['Ποιος', 'Πού', 'Τηλέφωνο']);
      final phone = doc.fields.firstWhere((f) => f.label == 'Τηλέφωνο');
      expect(phone.value, '2531');
      expect(
        phone.emphasized,
        isTrue,
        reason: 'φτάνοντας στο τμήμα, αυτό ψάχνει πρώτο ο τεχνικός',
      );
    });

    test('ό,τι λείπει δεν αφήνει ετικέτα με παύλα', () {
      final doc = buildTaskPrintDocument(
        _task(userText: null, phoneText: '   ', equipmentText: null),
      );

      expect(doc.fields.map((f) => f.label), ['Πού']);
    });

    test('ο εξοπλισμός μπαίνει όταν υπάρχει', () {
      final doc = buildTaskPrintDocument(_task(equipmentText: '3505'));

      expect(
        doc.fields.map((f) => f.label),
        containsAll(['Τηλέφωνο', 'Εξοπλισμός']),
      );
    });
  });

  group('οι δεσμοί', () {
    test('η κλήση και το αίτημα μπαίνουν σε μία γραμμή', () {
      final doc = buildTaskPrintDocument(
        _task(callId: 444, lansweeperMainTicketId: '60011'),
      );

      expect(doc.linkLine, 'Από κλήση #444 · Αίτημα Lansweeper #60011');
    });

    test('μόνο η κλήση, όταν δεν έχει σταλεί ποτέ', () {
      expect(
        buildTaskPrintDocument(_task(callId: 444)).linkLine,
        'Από κλήση #444',
      );
    });

    test('αυτόνομη εκκρεμότητα δεν έχει γραμμή δεσμού', () {
      expect(buildTaskPrintDocument(_task()).linkLine, isNull);
    });
  });

  group('το ιστορικό αναβολών', () {
    String snoozes() => jsonEncode([
      {
        'snoozedAt': '2026-09-02T12:00:00.000',
        'dueAt': '2026-09-03T09:00:00.000',
        'note': 'περιμένω τον ηλεκτρολόγο',
      },
      {
        'snoozedAt': '2026-09-03T09:30:00.000',
        'dueAt': '2026-09-05T09:00:00.000',
      },
    ]);

    test('κάθε αναβολή αριθμείται με τη σειρά της', () {
      final doc = buildTaskPrintDocument(_task(snoozeHistoryJson: snoozes()));

      expect(doc.hasSnoozes, isTrue);
      expect(doc.snoozes, hasLength(2));
      expect(doc.snoozes.first.order, 1);
      expect(doc.snoozes.first.movedAt, '02/09/2026 12:00');
      expect(doc.snoozes.first.newDueAt, '03/09/2026 09:00');
      expect(doc.snoozes.first.note, 'περιμένω τον ηλεκτρολόγο');
    });

    test('αναβολή χωρίς λόγο δεν επινοεί κανέναν', () {
      final doc = buildTaskPrintDocument(_task(snoozeHistoryJson: snoozes()));

      expect(doc.snoozes.last.note, isNull);
      expect(doc.snoozes.last.order, 2);
    });

    test('χωρίς αναβολές, η ενότητα δεν υπάρχει', () {
      expect(buildTaskPrintDocument(_task()).hasSnoozes, isFalse);
    });
  });

  group('η προηγούμενη ολοκλήρωση', () {
    test('η λύση και η στιγμή της μπαίνουν στο χαρτί', () {
      final doc = buildTaskPrintDocument(
        _task(
          status: 'closed',
          completedAt: '2026-09-04T17:36:00.000',
          solutionNotes: 'Αντικαταστάθηκε το καλώδιο UTP.',
        ),
      );

      expect(doc.hasClosure, isTrue);
      expect(doc.previousSolution, 'Αντικαταστάθηκε το καλώδιο UTP.');
      expect(doc.completionLine, startsWith('Ολοκληρώθηκε 04/09/2026 17:36'));
    });

    test('ανοιχτή εκκρεμότητα δεν έχει ενότητα ολοκλήρωσης', () {
      expect(buildTaskPrintDocument(_task()).hasClosure, isFalse);
    });

    test('μετρά και ο χρόνος από την τελευταία αναβολή', () {
      final doc = buildTaskPrintDocument(
        _task(
          status: 'closed',
          completedAt: '2026-09-04T17:36:00.000',
          snoozeHistoryJson: jsonEncode([
            {'snoozedAt': '2026-09-03T09:30:00.000'},
          ]),
        ),
      );

      expect(doc.sinceLastSnoozeLine, isNotNull);
      expect(doc.sinceLastSnoozeLine, startsWith('Από την τελευταία αναβολή:'));
    });
  });
}
