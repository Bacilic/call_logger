// Η εικόνα πατρόν κρατιέται όσο το αποτύπωμά της δεν αλλάζει, και η μνήμη
// δεν μεγαλώνει χωρίς όριο.
//
//   flutter test test/features/directory/building_map/plan/services/floor_plan_pattern_cache_test.dart

import 'dart:typed_data';

import 'package:call_logger/features/directory/building_map/plan/services/floor_plan_pattern_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List image(int bytes) => Uint8List(bytes);

  test('ίδιο αποτύπωμα: η εικόνα επιστρέφεται χωρίς νέο κατέβασμα', () {
    final cache = FloorPlanPatternCache();
    cache.put('abc', image(1000));

    expect(cache.get('abc'), isNotNull);
    expect(cache.get('abc')!.lengthInBytes, 1000);
  });

  test('άλλο αποτύπωμα: η μνήμη δεν απαντά', () {
    // Ο συνάδελφος φόρτωσε νέα κάτοψη από άλλον σταθμό. Η επόμενη ανάγνωση
    // κατάστασης φέρνει άλλο αποτύπωμα, οπότε η νέα εικόνα πρέπει να κατέβει.
    final cache = FloorPlanPatternCache();
    cache.put('abc', image(1000));

    expect(cache.get('def'), isNull);
  });

  test('χωρίς αποτύπωμα δεν κρατιέται και δεν απαντιέται τίποτα', () {
    final cache = FloorPlanPatternCache();
    cache.put(null, image(1000));

    expect(cache.length, 0);
    expect(cache.get(null), isNull);
  });

  test(
    'όταν γεμίσει, φεύγει η εικόνα που δεν ζητήθηκε για περισσότερη ώρα',
    () {
      final cache = FloorPlanPatternCache(maxBytes: 2500);
      cache.put('a', image(1000));
      cache.put('b', image(1000));
      // Το «a» ζητιέται ξανά, οπότε το «b» είναι πια το παλιότερο σε χρήση.
      cache.get('a');
      cache.put('c', image(1000));

      expect(cache.get('a'), isNotNull);
      expect(cache.get('c'), isNotNull);
      expect(cache.get('b'), isNull);
      expect(cache.heldBytes, 2000);
    },
  );

  test(
    'εικόνα μεγαλύτερη από το όριο δεν αδειάζει τη μνήμη για να χωρέσει',
    () {
      final cache = FloorPlanPatternCache(maxBytes: 2000);
      cache.put('small', image(500));
      cache.put('huge', image(5000));

      expect(cache.get('small'), isNotNull, reason: 'η μικρή μένει');
      expect(cache.get('huge'), isNull, reason: 'η τεράστια δεν κρατιέται');
      expect(cache.heldBytes, 500);
    },
  );

  test('η ίδια εικόνα δύο φορές δεν μετριέται δύο φορές', () {
    final cache = FloorPlanPatternCache();
    cache.put('abc', image(1000));
    cache.put('abc', image(1000));

    expect(cache.length, 1);
    expect(cache.heldBytes, 1000);
  });
}
