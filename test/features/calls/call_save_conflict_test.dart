// Τι λέει ο διάλογος διένεξης κλήσης — καθαρή λογική, χωρίς βάση και οθόνη.
//
//   flutter test test/features/calls/call_save_conflict_test.dart

import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/services/call_save_conflict.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CallModel call({
    String issue = 'Δεν τυπώνει ο εκτυπωτής',
    String? solution,
    String state = 'unsent',
    String? ticket,
  }) => CallModel(
    id: 500,
    date: '2026-08-24',
    time: '13:05',
    issue: issue,
    solution: solution,
    status: 'completed',
    lansweeperState: state,
    lansweeperMainTicketId: ticket,
  );

  final now = DateTime(2026, 8, 24, 13, 12);
  final changedAt = DateTime(2026, 8, 24, 13, 10);

  test('ο συνάδελφος καταχώρησε: το μήνυμα προειδοποιεί για ΔΕΥΤΕΡΟ αίτημα', () {
    final conflict = CallSaveConflict(
      expected: call(),
      fresh: call(state: 'sent', ticket: '8001'),
      attempted: call(issue: 'διορθωμένο'),
      changedBy: 'Βλάσης',
      changedAt: changedAt,
    );

    expect(conflict.otherRegisteredInLansweeper, isTrue);
    expect(conflict.headline(now: now), contains('Βλάσης'));
    expect(conflict.headline(now: now), contains('Lansweeper'));
    expect(conflict.headline(now: now), contains('13:10'));
    expect(conflict.overwriteWarning, contains('8001'));
    expect(
      conflict.overwriteWarning,
      contains('ΔΕΥΤΕΡΟ'),
      reason: 'η μη αναστρέψιμη συνέπεια πρέπει να λέγεται ρητά',
    );
  });

  test('η αλλαγή γράφεται με τις ετικέτες του Ιστορικού', () {
    final conflict = CallSaveConflict(
      expected: call(),
      fresh: call(state: 'sent', ticket: '8001'),
      attempted: call(issue: 'διορθωμένο'),
    );

    expect(conflict.changedFields, contains('κατάσταση Lansweeper'));
    expect(
      conflict.changedFields.any((f) => f.contains('_')),
      isFalse,
      reason: 'κανένα ωμό όνομα στήλης δεν φτάνει στην οθόνη',
    );
  });

  test('απλή ξένη διόρθωση κειμένου: χωρίς προειδοποίηση αιτήματος', () {
    final conflict = CallSaveConflict(
      expected: call(),
      fresh: call(issue: 'το άλλαξε ο συνάδελφος'),
      attempted: call(issue: 'το άλλαξα εγώ'),
      changedBy: 'Βλάσης',
      changedAt: changedAt,
    );

    expect(conflict.otherRegisteredInLansweeper, isFalse);
    expect(conflict.headline(now: now), contains('άλλαξε αυτή την κλήση'));
    expect(conflict.overwriteWarning, isNot(contains('ΔΕΥΤΕΡΟ')));
  });

  test('σβησμένη τιμή μετράει ως αλλαγή', () {
    // Το toMap() παραλείπει τα κενά πεδία· αν η σύγκριση πατούσε σε εκείνο,
    // το «είχε λύση και σβήστηκε» θα περνούσε για «δεν άλλαξε τίποτα».
    final conflict = CallSaveConflict(
      expected: call(solution: 'Αντικαταστάθηκε το τόνερ'),
      fresh: call(),
      attempted: call(solution: 'Αντικαταστάθηκε το τόνερ'),
    );

    expect(conflict.hasChanges, isTrue);
  });

  test('καμία διαφορά σημαίνει καμία διένεξη', () {
    final conflict = CallSaveConflict(
      expected: call(),
      fresh: call(),
      attempted: call(issue: 'η δική μου αλλαγή'),
    );

    expect(
      conflict.hasChanges,
      isFalse,
      reason: 'οι δικές μου αλλαγές δεν είναι ξένες',
    );
  });

  test('η ώρα παίρνει ημερομηνία όταν δεν είναι σήμερα', () {
    final conflict = CallSaveConflict(
      expected: call(),
      fresh: call(issue: 'άλλο'),
      attempted: call(),
      changedBy: 'Βλάσης',
      changedAt: DateTime(2026, 8, 22, 9, 5),
    );

    expect(conflict.headline(now: now), contains('22/08 09:05'));
  });
}
