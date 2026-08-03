import 'package:call_logger/core/utils/id_search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdSearchQuery.parse', () {
    test('σκέτο «#243» δίνει id χωρίς κείμενο', () {
      final q = IdSearchQuery.parse('#243');
      expect(q.ids, [243]);
      expect(q.hasInvalidIdToken, false);
      expect(q.text, '');
    });

    test('μικτό «#243 βαρβαρα» χωρίζει id και κείμενο', () {
      final q = IdSearchQuery.parse('#243 βαρβαρα');
      expect(q.ids, [243]);
      expect(q.text, 'βαρβαρα');
    });

    test('«#αβγ» και σκέτο «#» είναι άκυροι όροι id', () {
      expect(IdSearchQuery.parse('#αβγ').hasInvalidIdToken, true);
      expect(IdSearchQuery.parse('#').hasInvalidIdToken, true);
    });

    test('κείμενο χωρίς «#» δεν έχει όρους id', () {
      final q = IdSearchQuery.parse('βαρβαρα 243');
      expect(q.hasIdTokens, false);
      expect(q.text, 'βαρβαρα 243');
    });
  });

  group('IdSearchQuery.matchesEntityId', () {
    test('ακριβές ταίριασμα — το «#243» δεν πιάνει το 1243', () {
      final q = IdSearchQuery.parse('#243');
      expect(q.matchesEntityId(243), true);
      expect(q.matchesEntityId(1243), false);
      expect(q.matchesEntityId(null), false);
    });

    test('χωρίς όρους id όλα περνούν', () {
      final q = IdSearchQuery.parse('βαρβαρα');
      expect(q.matchesEntityId(5), true);
      expect(q.matchesEntityId(null), true);
    });

    test('άκυρος όρος id δεν ταιριάζει τίποτα', () {
      final q = IdSearchQuery.parse('#αβγ');
      expect(q.matchesEntityId(243), false);
    });
  });

  group('IdSearchQuery βοηθητικά όρων', () {
    test('isIdToken/parseIdToken', () {
      expect(IdSearchQuery.isIdToken('#243'), true);
      expect(IdSearchQuery.isIdToken(' 243'), false);
      expect(IdSearchQuery.parseIdToken('#243'), 243);
      expect(IdSearchQuery.parseIdToken('#αβγ'), null);
      expect(IdSearchQuery.parseIdToken('243'), null);
    });
  });
}
