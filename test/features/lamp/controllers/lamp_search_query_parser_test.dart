import 'package:call_logger/features/lamp/controllers/lamp_search_query_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LampSearchQueryParser', () {
    test('αναγνωρίζει απλό στοχευμένο φίλτρο με κενά γύρω από το :', () {
      final result = LampSearchQueryParser.parse('κατηγορια: υπολογιστης');

      expect(result.freeText, isEmpty);
      expect(result.scopedTerms, hasLength(1));
      expect(result.scopedTerms.single.columns, contains('category_name'));
      expect(result.scopedTerms.single.value, 'υπολογιστης');
    });

    test('αναγνωρίζει στοχευμένο φίλτρο χωρίς τόνους στο κλειδί', () {
      final result = LampSearchQueryParser.parse('κατηγορία:υπολογιστής');

      expect(result.scopedTerms, hasLength(1));
      expect(result.scopedTerms.single.value, 'υπολογιστής');
    });

    test('τιμή σε εισαγωγικά με κενά', () {
      final result = LampSearchQueryParser.parse('τμήμα:"Ιατρική Υπηρεσία"');

      expect(result.scopedTerms, hasLength(1));
      expect(result.scopedTerms.single.columns, contains('office_name'));
      expect(result.scopedTerms.single.value, 'Ιατρική Υπηρεσία');
    });

    test('πολλαπλά φίλτρα = λογικό ΚΑΙ + ελεύθερο κείμενο', () {
      final result = LampSearchQueryParser.parse(
        'κατηγορια:υπολογιστης ip:10.10 ελεύθερο',
      );

      expect(result.scopedTerms, hasLength(2));
      expect(result.scopedTerms[0].columns, contains('category_name'));
      expect(result.scopedTerms[0].value, 'υπολογιστης');
      expect(result.scopedTerms[1].columns, contains('ip_address'));
      expect(result.scopedTerms[1].value, '10.10');
      expect(result.freeText, 'ελεύθερο');
    });

    test('συνώνυμο sn για σειριακό', () {
      final result = LampSearchQueryParser.parse('sn:ABC123');

      expect(result.scopedTerms.single.columns, contains('serial_no'));
      expect(result.scopedTerms.single.value, 'ABC123');
    });

    test('συνώνυμο hostname / υπολογιστής για network_name', () {
      for (final query in <String>['hostname:PR3900', 'υπολογιστης:PR3900']) {
        final result = LampSearchQueryParser.parse(query);
        expect(
          result.scopedTerms.single.columns,
          contains('network_name'),
          reason: query,
        );
      }
    });

    test('σύμβαση-κατηγορία με παύλα στο κλειδί', () {
      final result = LampSearchQueryParser.parse('σύμβαση-κατηγορία:Υλικό');

      expect(result.scopedTerms.single.columns, contains('contract_category_name'));
      expect(result.scopedTerms.single.value, 'Υλικό');
    });

    test('άγνωστο κλειδί → ολόκληρο κομμάτι ως ελεύθερο κείμενο', () {
      final result = LampSearchQueryParser.parse('άγνωστο:τιμή');

      expect(result.scopedTerms, isEmpty);
      expect(result.freeText, 'άγνωστο:τιμή');
    });

    test('γνωστό κλειδί χωρίς τιμή → ελεύθερο κείμενο', () {
      final result = LampSearchQueryParser.parse('κατηγορια:');

      expect(result.scopedTerms, isEmpty);
      expect(result.freeText, 'κατηγορια:');
    });

    test('κείμενο χωρίς σύνταξη κλειδιών → μόνο ελεύθερο κείμενο', () {
      final result = LampSearchQueryParser.parse('βασιλης δροσος');

      expect(result.scopedTerms, isEmpty);
      expect(result.freeText, 'βασιλης δροσος');
    });

    test('καθρέφτισμα πεδίων φίλτρων για γνωστά κλειδιά', () {
      expect(
        LampSearchQueryParser.mirrorFieldIdForKey('τηλέφωνο'),
        'phone',
      );
      expect(LampSearchQueryParser.mirrorFieldIdForKey('κωδικός'), 'code');
      expect(LampSearchQueryParser.mirrorFieldIdForKey('υπάλληλος'), 'owner');
      expect(LampSearchQueryParser.mirrorFieldIdForKey('όνομα'), 'owner');
      expect(LampSearchQueryParser.mirrorFieldIdForKey('τμήμα'), 'office');
      expect(LampSearchQueryParser.mirrorFieldIdForKey('σειριακός'), 'serial');
      expect(LampSearchQueryParser.mirrorFieldIdForKey('sn'), 'serial');
      expect(LampSearchQueryParser.mirrorFieldIdForKey('κατηγορία'), isNull);
    });

    test('suggestKeys ταιριάζει χωρίς τόνους/πεζά', () {
      final suggestions = LampSearchQueryParser.suggestKeys('κατηγ');
      expect(suggestions, contains('κατηγορία'));
    });

    test('suggestKeys επιστρέφει όλα τα κλειδιά για κενό prefix', () {
      final suggestions = LampSearchQueryParser.suggestKeys('');
      expect(suggestions, isNotEmpty);
      expect(suggestions, contains('ip'));
      expect(suggestions, contains('τμήμα'));
    });
  });
}
