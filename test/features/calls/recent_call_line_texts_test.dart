// Τι διαβάζει ο χειριστής σε μία γραμμή του πρόσφατου ιστορικού, και τι κρύβει
// η υπόδειξη από πίσω.
//
//   flutter test test/features/calls/recent_call_line_texts_test.dart

import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/screens/widgets/recent_call_line_texts.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η πραγματική μορφή των περιγραφών που γράφει η ΤΝ: 43% των 493 κλήσεων της
/// βάσης ξεκινούν έτσι.
const String _kAiIssue =
    'Το τμήμα Ψυχιατρική αναφέρει ότι στον υπολογιστή 3894 υπάρχει δυσκολία '
    'στην ανεύρεση της αναφοράς για κάγκελα.';
const String _kTitle = 'Δυσκολία ανεύρεσης αναφοράς για κάγκελα';
const String _kSolution = 'Πραγματοποιήθηκε αναζήτηση στο docutracks.';

CallModel _call({String? title, String? issue, String? solution}) =>
    CallModel(title: title, issue: issue, solution: solution);

void main() {
  group('Τι δείχνει η γραμμή', () {
    test('με τίτλο δείχνει τον τίτλο, όχι την περιγραφή', () {
      expect(
        recentCallLineText(_call(title: _kTitle, issue: _kAiIssue)),
        _kTitle,
      );
    });

    test('χωρίς τίτλο δείχνει την περιγραφή, όπως πάντα', () {
      expect(recentCallLineText(_call(issue: _kAiIssue)), _kAiIssue);
    });

    test('κενός τίτλος μετράει σαν να μην υπάρχει', () {
      expect(
        recentCallLineText(_call(title: '   ', issue: _kAiIssue)),
        _kAiIssue,
      );
    });

    test('χωρίς τίποτα γραμμένο μένει η παύλα', () {
      expect(recentCallLineText(_call()), '—');
    });
  });

  group('Τι λέει η υπόδειξη', () {
    test('με τίτλο δείχνει πρόβλημα ΚΑΙ λύση', () {
      final text = recentCallTooltipText(
        _call(title: _kTitle, issue: _kAiIssue, solution: _kSolution),
      );

      expect(text, contains('Πρόβλημα: $_kAiIssue'));
      expect(text, contains('Λύση: $_kSolution'));
    });

    test('η περιγραφή δεν επαναλαμβάνεται όταν τη δείχνει ήδη η γραμμή', () {
      final text = recentCallTooltipText(
        _call(issue: _kAiIssue, solution: _kSolution),
      );

      expect(
        text,
        isNot(contains('Πρόβλημα:')),
        reason: 'Χωρίς τίτλο, η γραμμή ΕΙΝΑΙ η περιγραφή.',
      );
      expect(text, contains('Λύση: $_kSolution'));
    });

    test('χωρίς λύση και χωρίς τίτλο δεν υπάρχει υπόδειξη', () {
      expect(recentCallTooltipText(_call(issue: _kAiIssue)), isEmpty);
    });

    test('η λύση φαίνεται ακόμη κι όταν λείπει η περιγραφή', () {
      expect(
        recentCallTooltipText(_call(solution: _kSolution)),
        'Λύση: $_kSolution',
      );
    });

    test('κλήση χωρίς τίποτα δεν γεννά υπόδειξη', () {
      expect(recentCallTooltipText(_call()), isEmpty);
    });
  });
}
