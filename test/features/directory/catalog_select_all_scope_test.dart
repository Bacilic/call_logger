// Το κουτάκι της κεφαλίδας αφορά ΜΟΝΟ ό,τι δείχνει η λίστα τώρα — ποτέ ό,τι
// έχει φιλτραριστεί έξω.
//
//   flutter test test/features/directory/catalog_select_all_scope_test.dart

import 'package:call_logger/features/directory/screens/widgets/catalog_select_all_checkbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Τι δείχνει το κουτάκι της κεφαλίδας', () {
    test('όλα τα ορατά επιλεγμένα → τσεκαρισμένο', () {
      expect(
        catalogSelectAllValue(visibleIds: const [1, 2], selectedIds: {1, 2, 9}),
        isTrue,
      );
    });

    test('κανένα ορατό επιλεγμένο → άδειο', () {
      expect(
        catalogSelectAllValue(visibleIds: const [1, 2], selectedIds: {9}),
        isFalse,
      );
    });

    test('μερικά ορατά επιλεγμένα → ενδιάμεσο, όχι άδειο', () {
      expect(
        catalogSelectAllValue(visibleIds: const [1, 2, 3], selectedIds: {2}),
        isNull,
      );
    });

    test('άδεια λίστα → άδειο', () {
      expect(
        catalogSelectAllValue(visibleIds: const [], selectedIds: {1, 2}),
        isFalse,
      );
    });
  });

  group('Τι αλλάζει το πάτημα', () {
    test('από «όλα τα ορατά» ξε-επιλέγει ΜΟΝΟ τα ορατά', () {
      // Το σενάριο του σφάλματος: 5 επιλεγμένοι, η αναζήτηση δείχνει 2.
      final targets = catalogSelectAllToggleTargets(
        visibleIds: const [1, 2],
        selectedIds: {1, 2, 7, 8, 9},
      );

      expect(
        targets,
        [1, 2],
        reason:
            'Οι 7, 8 και 9 δεν φαίνονται καν — το κουτάκι δεν έχει δικαίωμα '
            'πάνω τους.',
      );
    });

    test('από «κανένα» επιλέγει τα ορατά που λείπουν', () {
      expect(
        catalogSelectAllToggleTargets(
          visibleIds: const [1, 2, 3],
          selectedIds: {7},
        ),
        [1, 2, 3],
      );
    });

    test('από «μερικά» συμπληρώνει, δεν αδειάζει', () {
      expect(
        catalogSelectAllToggleTargets(
          visibleIds: const [1, 2, 3],
          selectedIds: {2, 7},
        ),
        [1, 3],
      );
    });

    test('άδεια λίστα δεν αλλάζει τίποτα', () {
      expect(
        catalogSelectAllToggleTargets(visibleIds: const [], selectedIds: {1}),
        isEmpty,
      );
    });
  });

  group('CatalogSelectAllCheckbox (widget)', () {
    testWidgets('το πάτημα αφήνει άθικτες τις κρυμμένες επιλογές', (
      tester,
    ) async {
      final toggled = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogSelectAllCheckbox(
              visibleIds: const [1, 2],
              selectedIds: const {1, 2, 7, 8, 9},
              onToggleSelection: toggled.add,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(toggled, [1, 2]);
    });

    testWidgets('χωρίς ορατές γραμμές το κουτάκι δεν πατιέται', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogSelectAllCheckbox(
              visibleIds: const [],
              selectedIds: const {1},
              onToggleSelection: (_) {},
            ),
          ),
        ),
      );

      expect(
        tester.widget<Checkbox>(find.byType(Checkbox)).onChanged,
        isNull,
        reason: 'Άδεια λίστα: δεν υπάρχει τίποτα να επιλεγεί ή να αφαιρεθεί.',
      );
    });
  });
}
