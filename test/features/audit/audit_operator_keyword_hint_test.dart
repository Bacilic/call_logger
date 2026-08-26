// Η λογική της υπόδειξης «μήπως ψάχνετε χειριστή;» στο Ιστορικό Εφαρμογής.
//
//   flutter test test/features/audit/audit_operator_keyword_hint_test.dart

import 'package:call_logger/features/audit/services/audit_operator_keyword_hint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const operators = ['Βασίλης', 'Bacilic', '—'];

  group('Ταίριασμα λέξης με χειριστή', () {
    test('πρόθεμα ονόματος χωρίς τόνους βρίσκει τον χειριστή', () {
      final suggestions = operatorKeywordSuggestions('βασι', operators);

      expect(suggestions, hasLength(1));
      expect(suggestions.single.operatorName, 'Βασίλης');
      expect(suggestions.single.matchedWord, 'βασι');
    });

    test('η λέξη βρίσκεται ανάμεσα σε άλλες', () {
      final suggestions = operatorKeywordSuggestions('χρη βασι', operators);

      expect(suggestions.single.operatorName, 'Βασίλης');
      expect(suggestions.single.matchedWord, 'βασι');
    });

    test('λέξεις κάτω από 3 χαρακτήρες δεν προτείνουν τίποτα', () {
      expect(operatorKeywordSuggestions('βα', operators), isEmpty);
    });

    test('άσχετη λέξη δεν προτείνει τίποτα', () {
      expect(operatorKeywordSuggestions('πρωτόκολλο', operators), isEmpty);
    });

    test('ο ήδη επιλεγμένος χειριστής δεν ξαναπροτείνεται', () {
      final suggestions = operatorKeywordSuggestions(
        'βασι',
        operators,
        alreadySelected: 'Βασίλης',
      );

      expect(suggestions, isEmpty);
    });

    test('το πρόθεμα πιάνει και το δεύτερο μέρος του ονόματος', () {
      final suggestions = operatorKeywordSuggestions('δρόσος', [
        'Βασίλης Δρόσος',
      ]);

      expect(suggestions.single.operatorName, 'Βασίλης Δρόσος');
    });

    test('κενό κείμενο δεν προτείνει τίποτα', () {
      expect(operatorKeywordSuggestions('   ', operators), isEmpty);
    });
  });

  group('Αφαίρεση της λέξης μετά την αποδοχή', () {
    test('η λέξη φεύγει και οι υπόλοιπες μένουν', () {
      expect(keywordWithoutWord('χρη βασι', 'βασι'), 'χρη');
    });

    test('μόνη της λέξη αφήνει κενό πεδίο', () {
      expect(keywordWithoutWord('βασι', 'βασι'), '');
    });

    test('αφαιρείται μία εμφάνιση, όχι όλες', () {
      expect(keywordWithoutWord('βασι βασι', 'βασι'), 'βασι');
    });
  });
}
