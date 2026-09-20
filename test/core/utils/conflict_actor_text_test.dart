import 'dart:io';

import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/utils/conflict_actor_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 22, 13, 10);

  group('ποιος πρόλαβε', () {
    test('το όνομα γράφεται όπως το ξέρει ο αναγνώστης', () {
      expect(conflictActorName('Βασίλης'), 'Ο χρήστης «Βασίλης»');
    });

    test('χωρίς όνομα δεν κατηγορείται κανείς', () {
      expect(conflictActorName(null), 'Κάποιος άλλος');
      expect(conflictActorName('   '), 'Κάποιος άλλος');
    });

    // Η παύλα είναι η σφραγίδα «δεν ξέρουμε ποιος» του Ιστορικού, όχι όνομα:
    // η βάση την επιστρέφει για κάθε εγγραφή γραμμένη πριν αποκτήσει η
    // εφαρμογή ταυτότητα χειριστή.
    test('η παύλα του Ιστορικού δεν περνά ως όνομα', () {
      expect(
        conflictActorName(CurrentOperator.unknownAuditName),
        'Κάποιος άλλος',
      );
    });
  });

  group('και πότε', () {
    test('σήμερα γράφεται σκέτη ώρα', () {
      expect(
        conflictMomentSuffix(DateTime(2026, 8, 22, 9, 5), now: now),
        ' στις 09:05',
      );
    });

    // Το σκέτο «στις 18:00» για κάτι που έγινε προχθές διαβάζεται ως σημερινό.
    test('παλιότερα παίρνει και ημερομηνία', () {
      expect(
        conflictMomentSuffix(DateTime(2026, 8, 20, 9, 15), now: now),
        ' στις 20/08 09:15',
      );
    });

    test('άγνωστη ώρα δεν προσθέτει τίποτα', () {
      expect(conflictMomentSuffix(null, now: now), '');
    });
  });

  // Ο κοινός βοηθός αξίζει μόνο αν τον ρωτούν ΟΛΟΙ οι φρουροί. Έλεγχος πηγαίου
  // κώδικα και όχι συμπεριφοράς: το ζητούμενο είναι «ποιος κατέχει τη
  // διατύπωση», δηλαδή δομή, όχι υπολογισμός.
  test('κανένας φρουρός διένεξης δεν ξαναγράφει το «ποιος και πότε»', () {
    const guards = [
      'lib/core/services/settings_list_conflict.dart',
      'lib/features/calls/services/call_save_conflict.dart',
      'lib/features/directory/services/directory_save_conflict.dart',
      'lib/features/history/services/lansweeper_registration_conflict.dart',
      'lib/features/operators/services/operator_save_conflict.dart',
      'lib/features/tasks/services/task_conflict_summary.dart',
    ];
    for (final guard in guards) {
      final source = File(
        '${Directory.current.path}${Platform.pathSeparator}'
        '${guard.replaceAll('/', Platform.pathSeparator)}',
      ).readAsStringSync();
      expect(
        source.contains("'Κάποιος άλλος'"),
        isFalse,
        reason:
            'Το «$guard» ξαναγράφει το υποκείμενο — και μαζί χάνει τον χειρισμό '
            'της παύλας του Ιστορικού.',
      );
      expect(
        source.contains('padLeft(2'),
        isFalse,
        reason: 'Το «$guard» ξαναγράφει τον μορφοποιητή της ώρας.',
      );
      expect(
        source.contains('conflictActorName'),
        isTrue,
        reason: 'Το «$guard» οφείλει να ρωτά τον κοινό βοηθό.',
      );
    }
  });
}
