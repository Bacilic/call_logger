// Η αποτυχία φόρτωσης κατόψεων δεν μεταμφιέζεται σε άδεια λίστα.
//
// Ως τώρα η καρτέλα τμήματος σημάδευε την αποτυχία ως ολοκληρωμένη φόρτωση:
// ο χαρτογραφημένος όροφος εμφανιζόταν «δεν βρέθηκε κάτοψη», και όποιος
// πίστευε το μήνυμα και επέλεγε «— χωρίς —» έσβηνε τη θέση του τμήματος στον
// χάρτη κτιρίου.
//
//   flutter test test/features/directory/building_map_floor_load_state_test.dart

import 'package:call_logger/features/directory/services/building_map_floor_load_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('κατάσταση φόρτωσης κατόψεων', () {
    test('η αποτυχία ΔΕΝ περνά για ολοκληρωμένη φόρτωση', () {
      expect(BuildingMapFloorLoadState.failed.isLoaded, isFalse);
      expect(BuildingMapFloorLoadState.loading.isLoaded, isFalse);
      expect(BuildingMapFloorLoadState.loaded.isLoaded, isTrue);
    });

    test('χωρίς διαβασμένες κατόψεις, ο όροφος δεν αλλάζει', () {
      // Η μόνη διαθέσιμη επιλογή θα ήταν «— χωρίς —», που σβήνει τη
      // χαρτογράφηση: θέση, διαστάσεις, περιστροφή.
      expect(BuildingMapFloorLoadState.failed.allowsFloorChange, isFalse);
      expect(BuildingMapFloorLoadState.loading.allowsFloorChange, isFalse);
    });

    test('με διαβασμένες κατόψεις, η αλλαγή επιτρέπεται κανονικά', () {
      expect(BuildingMapFloorLoadState.loaded.allowsFloorChange, isTrue);
    });
  });

  group('μήνυμα κάτω από το πεδίο', () {
    test('η αποτυχία εξηγείται και δεν κατηγορεί τα δεδομένα', () {
      final notice = buildingMapFloorLoadNotice(
        BuildingMapFloorLoadState.failed,
      );
      expect(notice, isNotNull);
      expect(notice, contains('δεν φορτώθηκαν'));
      expect(
        notice,
        isNot(contains('δεν βρέθηκε')),
        reason: 'το μήνυμα δεν λέει ότι λείπει κάτι που απλώς δεν διαβάστηκε',
      );
    });

    test('κανονική φόρτωση: κανένα μήνυμα', () {
      expect(
        buildingMapFloorLoadNotice(BuildingMapFloorLoadState.loaded),
        isNull,
      );
      expect(
        buildingMapFloorLoadNotice(BuildingMapFloorLoadState.loading),
        isNull,
      );
    });
  });
}
