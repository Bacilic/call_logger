// Ο κανόνας «δείξε μόνο τα επιλεγμένα» — μία πηγή για τις τέσσερις καρτέλες.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/catalog_selection_filter_test.dart

import 'package:call_logger/features/directory/services/catalog_selection_filter.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row {
  const _Row(this.id, this.name);
  final int? id;
  final String name;
}

const _rows = <_Row>[
  _Row(1, 'Αιμοδοσία'),
  _Row(2, 'Βιοχημικό'),
  _Row(3, 'Καρδιολογική'),
  _Row(null, 'Χωρίς αναγνωριστικό'),
];

List<_Row> _filter(List<_Row> rows, bool active, Set<int> selected) {
  return applyCatalogSelectionFilter(
    rows,
    active: active,
    selectedIds: selected,
    idOf: (r) => r.id,
  );
}

void main() {
  group('catalogSelectionFilterStaysOn', () {
    test('με επιλογή, ο διακόπτης ισχύει', () {
      expect(
        catalogSelectionFilterStaysOn(requested: true, selectedIds: {1, 2}),
        isTrue,
      );
    });

    test('χωρίς επιλογή σβήνει μόνος του', () {
      expect(
        catalogSelectionFilterStaysOn(requested: true, selectedIds: const {}),
        isFalse,
      );
    });

    test('κλειστός διακόπτης μένει κλειστός όσες κι αν είναι οι επιλογές', () {
      expect(
        catalogSelectionFilterStaysOn(requested: false, selectedIds: {1, 2, 3}),
        isFalse,
      );
    });
  });

  group('applyCatalogSelectionFilter', () {
    test('κρατά μόνο τα επιλεγμένα', () {
      final result = _filter(_rows, true, {1, 3});
      expect(result.map((r) => r.name), ['Αιμοδοσία', 'Καρδιολογική']);
    });

    test('κλειστό φίλτρο αφήνει τη λίστα άθικτη', () {
      expect(_filter(_rows, false, {1}).length, _rows.length);
    });

    test('άδεια επιλογή αφήνει τη λίστα άθικτη αντί να την αδειάσει', () {
      expect(_filter(_rows, true, const {}).length, _rows.length);
    });

    test('γραμμή χωρίς αναγνωριστικό δεν περνά ποτέ το φίλτρο', () {
      final result = _filter(_rows, true, {1, 2, 3});
      expect(result.any((r) => r.id == null), isFalse);
    });

    test('η σειρά της λίστας διατηρείται', () {
      final result = _filter(_rows, true, {3, 1});
      expect(result.map((r) => r.id), [1, 3]);
    });

    test('επιλεγμένο που η αναζήτηση έκοψε δεν επανεμφανίζεται', () {
      // Η λίστα έρχεται ήδη φιλτραρισμένη από την αναζήτηση: το φίλτρο
      // επιλογής είναι τομή, όχι ένωση.
      final afterSearch = [_rows[1]];
      final result = _filter(afterSearch, true, {1, 2, 3});
      expect(result.map((r) => r.id), [2]);
    });
  });
}
