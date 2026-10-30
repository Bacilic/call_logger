// Σειρά εμφάνισης των κατόψεων: αριθμητικά κατά όροφο, παντού η ίδια.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/building_map/building_map_floor_ordering_test.dart

import 'package:call_logger/core/models/building_map_floor.dart';
import 'package:call_logger/features/directory/building_map/services/building_map_floor_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

BuildingMapFloor _floor(int id, String label, {String? group, int sort = 0}) {
  return BuildingMapFloor(
    id: id,
    sortOrder: sort,
    label: label,
    floorGroup: group,
    imagePath: '',
    rotationDegrees: 0,
  );
}

List<String> _labelsOf(List<BuildingMapFloor> floors) =>
    floors.map((f) => f.label).toList();

void main() {
  group('Σειρά κατόψεων', () {
    test('η σειρά της βάσης αγνοείται — ταξινομεί αριθμητικά κατά όροφο', () {
      // Ακριβώς η σειρά που έδειχνε η Προβολή χάρτη πριν τη διόρθωση.
      final floors = [
        _floor(1, '2ος - Καρδιολογική-Παθολογική-Ψυχιατρική'),
        _floor(2, '3ος - Χειρουργική-Ορθοπαιδική-Διοικητής'),
        _floor(3, '0 - Ισόγειο'),
        _floor(4, '1ος - Γραφεία'),
        _floor(5, '-1 - Υπόγειο'),
        _floor(6, '4ος - Παιδιατρική-Ουρολογική'),
      ];

      expect(_labelsOf(buildingMapFloorsSortedForDisplay(floors)), [
        '-1 - Υπόγειο',
        '0 - Ισόγειο',
        '1ος - Γραφεία',
        '2ος - Καρδιολογική-Παθολογική-Ψυχιατρική',
        '3ος - Χειρουργική-Ορθοπαιδική-Διοικητής',
        '4ος - Παιδιατρική-Ουρολογική',
      ]);
    });

    test('δύο υπόγεια: το βαθύτερο πρώτο', () {
      final floors = [
        _floor(1, '-1 - Υπόγειο'),
        _floor(2, '0 - Ισόγειο'),
        _floor(3, '-2 - Δεύτερο υπόγειο'),
      ];

      expect(_labelsOf(buildingMapFloorsSortedForDisplay(floors)), [
        '-2 - Δεύτερο υπόγειο',
        '-1 - Υπόγειο',
        '0 - Ισόγειο',
      ]);
    });

    test('διψήφιοι όροφοι: 2ος πριν από 10ος', () {
      final floors = [
        _floor(1, '10ος - Δώμα'),
        _floor(2, '2ος - Καρδιολογική'),
      ];

      expect(_labelsOf(buildingMapFloorsSortedForDisplay(floors)), [
        '2ος - Καρδιολογική',
        '10ος - Δώμα',
      ]);
    });

    // Ετικέτα χωρίς αριθμό δεν έχει «όροφο», οπότε μπαίνει στη θέση που όρισε ο
    // χρήστης με σύρσιμο — το `sort_order` διαβάζεται στην ίδια κλίμακα με τους
    // αριθμούς ορόφων.
    test('χωρίς αριθμό στην ετικέτα: πέφτει πίσω στο sort_order', () {
      final floors = [
        _floor(1, 'Πατάρι', sort: 9),
        _floor(2, 'Αποθήκη', sort: 3),
        _floor(3, '1ος - Γραφεία'),
      ];

      expect(_labelsOf(buildingMapFloorsSortedForDisplay(floors)), [
        '1ος - Γραφεία',
        'Αποθήκη',
        'Πατάρι',
      ]);
    });

    test('η αρχική λίστα δεν πειράζεται', () {
      final floors = [_floor(1, '2ος'), _floor(2, '1ος')];

      buildingMapFloorsSortedForDisplay(floors);

      expect(_labelsOf(floors), ['2ος', '1ος']);
    });
  });

  group('Ετικέτα εμφάνισης κάτοψης', () {
    test('με ομάδα: «ομάδα · ετικέτα»', () {
      final floor = _floor(1, '1ος - Γραφεία', group: 'Κτίριο Α');

      expect(buildingMapFloorDisplayLabel(floor), 'Κτίριο Α · 1ος - Γραφεία');
    });

    test('χωρίς ομάδα: σκέτη ετικέτα', () {
      expect(
        buildingMapFloorDisplayLabel(_floor(1, '0 - Ισόγειο')),
        '0 - Ισόγειο',
      );
    });
  });

  group('Σε ποιον όροφο ανοίγει ο χάρτης', () {
    // Περιστατικό 30/10/2026: μετά από επανεκκίνηση άνοιγε πάντα ο «2ος»,
    // γιατί ήταν πρώτος στην ωμή σειρά της βάσης.
    final floors = [
      _floor(1, '2ος - Καρδιολογική', sort: 0),
      _floor(2, '-1 - Υπόγειο', sort: 1),
      _floor(3, '0 - Ισόγειο', sort: 2),
    ];
    BuildingMapFloor withImage(BuildingMapFloor f) => BuildingMapFloor(
      id: f.id,
      sortOrder: f.sortOrder,
      label: f.label,
      imagePath: '',
      rotationDegrees: 0,
      imageHash: 'abc',
    );

    test('ο τελευταίος που είδε ο χρήστης κερδίζει τα πάντα', () {
      expect(
        chooseInitialBuildingMapFloor(
          floors: floors,
          rememberedId: 3,
          itFloorIds: {1},
        ),
        3,
      );
    });

    test('όροφος που σβήστηκε στο μεταξύ δεν θυμάται τίποτα', () {
      expect(
        chooseInitialBuildingMapFloor(
          floors: floors,
          rememberedId: 99,
          itFloorIds: {3},
        ),
        3,
      );
    });

    test('την πρώτη φορά: ο όροφος του τμήματος πληροφορικής', () {
      expect(chooseInitialBuildingMapFloor(floors: floors, itFloorIds: {3}), 3);
    });

    test('χωρίς πληροφορική: όροφος με κάτοψη ή νέο χάρτη', () {
      expect(
        chooseInitialBuildingMapFloor(
          floors: [floors[0], floors[1], withImage(floors[2])],
        ),
        3,
      );
      expect(
        chooseInitialBuildingMapFloor(floors: floors, newMapFloorIds: {1}),
        1,
      );
    });

    test('χωρίς τίποτα: ο πρώτος όπως φαίνεται στη λίστα, όχι στη βάση', () {
      expect(chooseInitialBuildingMapFloor(floors: floors), 2);
    });

    test('το τμήμα πληροφορικής αναγνωρίζεται από το όνομα', () {
      expect(isItDepartmentName('Τμήμα Πληροφορικής'), isTrue);
      expect(isItDepartmentName('ΠΛΗΡΟΦΟΡΙΚΗ'), isTrue);
      expect(isItDepartmentName('Καρδιολογική'), isFalse);
    });
  });
}
