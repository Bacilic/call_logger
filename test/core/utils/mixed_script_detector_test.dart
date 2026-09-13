import 'package:call_logger/core/utils/mixed_script_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ο ανιχνευτής αλλοιωμένων χαρακτήρων: τι σημαίνει, τι προσπερνά, και τι
/// προτείνει. Όλα τα παραδείγματα είναι αληθινές τιμές της βάσης Λάμπας.
void main() {
  // Ο τροποποιητής αποστρόφου που άφησε η παλιά εξαγωγή στη θέση του «Ά».
  // Γράφεται ως κωδικός, ώστε να μη χαθεί σε μετατροπή αρχείου.
  const broken = '\u02BC';
  // Έτοιμες λέξεις με τον χαλασμένο χαρακτήρα, ώστε το κείμενο των τεστ να
  // διαβάζεται χωρίς παρεμβολές μέσα σε ελληνικά.
  const brokenAnna = '\u02BCννα';
  const brokenAno = '\u02BCνω';

  MixedScriptFinding single(String value) {
    final findings = findMixedScriptWords(value);
    expect(findings, hasLength(1), reason: 'Αναμενόταν ένα εύρημα για «$value»');
    return findings.single;
  }

  group('χαλασμένος χαρακτήρας', () {
    test('η χαλασμένη «Άννα» σημαίνεται και διορθώνεται', () {
      final finding = single(brokenAnna);
      expect(finding.kind, MixedScriptKind.brokenCharacter);
      expect(finding.suggestion, 'Άννα');
    });

    test('και τα πέντε της βάσης παίρνουν πρόταση', () {
      const words = ['νω', 'σσου', 'δειες', 'ννα', 'γγελος'];
      for (final tail in words) {
        final finding = single('$broken$tail');
        expect(finding.suggestion, 'Ά$tail');
      }
    });

    test('απόστροφος μακριά από γράμμα δεν είναι εύρημα', () {
      expect(findMixedScriptWords('15$broken$broken'), isEmpty);
    });
  });

  group('μεικτά αλφάβητα', () {
    test('λατινικό γράμμα σε ελληνική λέξη: γίνεται ελληνικό', () {
      final finding = single('ΠΛΗΚΤΡΟΛΟΓΙO');
      expect(finding.kind, MixedScriptKind.mixedAlphabets);
      expect(finding.suggestion, 'ΠΛΗΚΤΡΟΛΟΓΙΟ');
    });

    test('ελληνικό γράμμα σε λατινικό κωδικό: γίνεται λατινικό', () {
      expect(single('ΜB451DN').suggestion, 'MB451DN');
      expect(single('ΟRIGINAL').suggestion, 'ORIGINAL');
    });

    test('ισοπαλία που λύνεται: το «z» δεν γίνεται ελληνικό', () {
      // Ένα γράμμα από το κάθε αλφάβητο, αλλά μόνο η μία μορφή είναι εφικτή.
      expect(single('Ηz').suggestion, 'Hz');
      expect(single('85Ηz').suggestion, '85Hz');
      expect(single('4GΒ').suggestion, '4GB');
    });

    test('ισοπαλία που ΔΕΝ λύνεται: εύρημα χωρίς πρόταση', () {
      // «Oι»: και οι δύο μορφές είναι εφικτές, και τα γράμματα ισοφαρίζουν.
      final finding = single('Oι');
      expect(finding.kind, MixedScriptKind.mixedAlphabets);
      expect(finding.suggestion, isNull);
      expect(finding.hasSuggestion, isFalse);
    });

    test('πλειοψηφία κρίνει όταν είναι εφικτά και τα δύο αλφάβητα', () {
      // «KITΡΙΝΟ»: γράφεται και ελληνικά και λατινικά· τα ελληνικά είναι
      // περισσότερα, οπότε κερδίζουν.
      expect(single('KITΡΙΝΟ').suggestion, 'ΚΙΤΡΙΝΟ');
    });

    test('γράμμα χωρίς οπτικό δίδυμο: εύρημα χωρίς πρόταση', () {
      // Το «g», «l», «s» δεν έχουν ελληνικό δίδυμο, οπότε η μεταγραφή θα
      // κατέστρεφε τη λέξη αντί να τη διορθώσει.
      expect(single('Σyglisis').suggestion, isNull);
    });

    test('παύλα χωρίζει λέξεις: το «e-Ραντεβού» δεν σημαίνεται', () {
      expect(findMixedScriptWords('e-Ραντεβού'), isEmpty);
    });
  });

  group('ψηφίο μέσα σε ελληνική λέξη', () {
    test('σειριακός με ελληνικά γράμματα: πρόταση σε λατινικά', () {
      final finding = single('Χ38Ν155345');
      expect(finding.kind, MixedScriptKind.digitInsideGreekWord);
      expect(finding.suggestion, 'X38N155345');
    });

    test('ελληνική λέξη με αριθμό: εύρημα χωρίς πρόταση', () {
      // «Ανάλυση1920Χ1080» — η μεταγραφή θα διέλυε τη λέξη «Ανάλυση».
      expect(single('Ανάλυση1920Χ1080').suggestion, isNull);
    });
  });

  group('τι ΔΕΝ σημαίνεται', () {
    test('σειριακοί, μοντέλα και τεχνικά χαρακτηριστικά περνούν καθαρά', () {
      const clean = [
        '133MHz',
        'GC03320570',
        'PC19',
        'B427W',
        '08606E7DFC4E',
        '1120C',
        'Αιματολογικό',
        'ORIGINAL',
        'ΠΛΗΚΤΡΟΛΟΓΙΟ',
        'Πατσαρίκα Άννα',
      ];
      for (final value in clean) {
        expect(
          findMixedScriptWords(value),
          isEmpty,
          reason: 'Το «$value» δεν είναι αλλοιωμένο',
        );
      }
    });

    test('κενό και κείμενο χωρίς λέξεις δεν σκάνε', () {
      expect(findMixedScriptWords(null), isEmpty);
      expect(findMixedScriptWords(''), isEmpty);
      expect(findMixedScriptWords('   '), isEmpty);
      expect(findMixedScriptWords('---'), isEmpty);
    });
  });

  group('εφαρμογή πρότασης στο πεδίο', () {
    test('αντικαθίσταται μόνο η λέξη, το υπόλοιπο κείμενο μένει', () {
      expect(
        applyMixedScriptSuggestion(
          'ΤΟΝΕΡ ΚΙΤΡΙΝΟ ΟRIGINAL HP',
          'ΟRIGINAL',
          'ORIGINAL',
        ),
        'ΤΟΝΕΡ ΚΙΤΡΙΝΟ ORIGINAL HP',
      );
    });

    test('η ίδια λέξη δύο φορές διορθώνεται και στις δύο', () {
      expect(
        applyMixedScriptSuggestion('ΜΟΤΟΡ και ΜΟΤΟΡ', 'ΜΟΤΟΡ', 'MOTOR'),
        'MOTOR και MOTOR',
      );
    });

    test('λέξη που περιέχεται σε άλλη δεν παρασύρεται', () {
      expect(
        applyMixedScriptSuggestion('ΜΟΤΟΡΑΚΙ ΜΟΤΟΡ', 'ΜΟΤΟΡ', 'MOTOR'),
        'ΜΟΤΟΡΑΚΙ MOTOR',
      );
    });
  });

  test('πολλές ύποπτες λέξεις στο ίδιο πεδίο βγαίνουν όλες', () {
    final findings = findMixedScriptWords(
      'ΟRIGINAL και ΜB451DN και $brokenAno',
    );
    expect(findings, hasLength(3));
    expect(
      findings.map((f) => f.kind).toSet(),
      {MixedScriptKind.mixedAlphabets, MixedScriptKind.brokenCharacter},
    );
    expect(
      findings.map((f) => f.suggestion).toList(),
      ['ORIGINAL', 'MB451DN', 'Άνω'],
    );
  });
}
