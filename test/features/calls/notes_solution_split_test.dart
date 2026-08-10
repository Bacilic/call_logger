// Η διάσπαση «τρέχουσα γραμμή → Λύση»: μεταφέρεται ΜΟΝΟ η γραμμή του κέρσορα,
// και ποτέ δεν αδειάζει το χαρτί σημειώσεων.
//
//   flutter test test/features/calls/notes_solution_split_test.dart

import 'package:call_logger/features/calls/utils/notes_solution_split.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Το όριο είναι ΕΝΑ για όλο το χαρτί: περιγραφή και λύση μοιράζονται τους
  // ίδιους χαρακτήρες, γιατί υπάρχει μόνο ως φράγμα σε τεράστια επικόλληση.
  group('NotesLengthBudget.limitFor', () {
    test('άδειο το άλλο πεδίο: ολόκληρο το όριο', () {
      expect(
        NotesLengthBudget.limitFor(currentLength: 10, otherLength: 0),
        kNotesTotalMaxLength,
      );
    });

    test('ό,τι κρατά το άλλο πεδίο αφαιρείται από το όριο', () {
      expect(
        NotesLengthBudget.limitFor(currentLength: 50, otherLength: 200),
        300,
      );
    });

    test('γεμάτο χαρτί: το πεδίο κλειδώνει στο τρέχον μήκος του', () {
      expect(
        NotesLengthBudget.limitFor(currentLength: 300, otherLength: 200),
        300,
      );
    });

    test('ΠΟΤΕ κάτω από τα ήδη γραμμένα — δεν κόβεται υπάρχον κείμενο', () {
      expect(
        NotesLengthBudget.limitFor(currentLength: 400, otherLength: 450),
        400,
      );
    });
  });

  group('NotesSolutionSplit.extractCurrentLine', () {
    test('κέρσορας στη δεύτερη γραμμή: κατεβαίνει αυτή, μένει η πρώτη', () {
      const text = 'Ο εκτυπωτής έχει κόκκινο λαμπάκι\nΈγινε αλλαγή τόνερ';

      final result = NotesSolutionSplit.extractCurrentLine(text, text.length);

      expect(result.movedLine, 'Έγινε αλλαγή τόνερ');
      expect(result.notes, 'Ο εκτυπωτής έχει κόκκινο λαμπάκι');
    });

    test('κέρσορας στη μέση της γραμμής, όχι στο τέλος: ίδια γραμμή', () {
      const text = 'πρόβλημα εδώ\nαλλαγή τόνερ';
      final offsetInsideSecondLine = text.indexOf('τόνερ');

      final result = NotesSolutionSplit.extractCurrentLine(
        text,
        offsetInsideSecondLine,
      );

      expect(result.movedLine, 'αλλαγή τόνερ');
      expect(result.notes, 'πρόβλημα εδώ');
    });

    test('ενδιάμεση γραμμή: οι υπόλοιπες ενώνονται χωρίς κενή τρύπα', () {
      const text = 'πρώτη γραμμή\nη λύση εδώ\nτρίτη γραμμή';
      final offsetInsideSecondLine = text.indexOf('λύση');

      final result = NotesSolutionSplit.extractCurrentLine(
        text,
        offsetInsideSecondLine,
      );

      expect(result.movedLine, 'η λύση εδώ');
      expect(result.notes, 'πρώτη γραμμή\nτρίτη γραμμή');
    });

    test('κέρσορας στην πρώτη γραμμή (από τις δύο): κατεβαίνει η πρώτη', () {
      const text = 'επανεκκίνηση εκτυπωτή\nδεν εκτυπώνει';

      final result = NotesSolutionSplit.extractCurrentLine(text, 0);

      expect(result.movedLine, 'επανεκκίνηση εκτυπωτή');
      expect(result.notes, 'δεν εκτυπώνει');
    });

    test('κενή γραμμή: δεν μεταφέρεται τίποτα', () {
      const text = 'μόνο πρόβλημα\n';

      final result = NotesSolutionSplit.extractCurrentLine(text, text.length);

      expect(result.movedLine, isEmpty);
      expect(result.notes, text);
    });

    test('μοναδική γραμμή: ΔΕΝ αδειάζει το χαρτί', () {
      const text = 'δεν εκτυπώνει η μπαρκοτιέρα';

      final result = NotesSolutionSplit.extractCurrentLine(text, 10);

      expect(result.movedLine, isEmpty);
      expect(result.notes, text);
    });

    test('πολλές γραμμές που όλες πλην μίας είναι κενές: ΔΕΝ αδειάζει', () {
      const text = '\n\nμόνο αυτή έχει κείμενο\n';
      final offset = text.indexOf('μόνο');

      final result = NotesSolutionSplit.extractCurrentLine(text, offset);

      expect(result.movedLine, isEmpty);
      expect(result.notes, text);
    });

    test('κενό κείμενο και offset εκτός ορίων δεν σκάνε', () {
      expect(
        NotesSolutionSplit.extractCurrentLine('', 5),
        (notes: '', movedLine: ''),
      );
      expect(
        NotesSolutionSplit.extractCurrentLine('α\nβ', 99).movedLine,
        'β',
      );
      expect(
        NotesSolutionSplit.extractCurrentLine('α\nβ', -3).movedLine,
        'α',
      );
    });
  });
}
