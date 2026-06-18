import 'package:call_logger/features/dictionary/dictionary_table_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lexiconRowsForColumnGroup', () {
    final rows = List.generate(
      10,
      (i) => {'display_word': 'w$i'},
    );

    test('distributes rows in newspaper column order', () {
      expect(
        lexiconRowsForColumnGroup(
          rows: rows,
          groupIndex: 0,
          columnsCount: 3,
        ).map((r) => r['display_word']),
        ['w0', 'w3', 'w6', 'w9'],
      );
      expect(
        lexiconRowsForColumnGroup(
          rows: rows,
          groupIndex: 1,
          columnsCount: 3,
        ).map((r) => r['display_word']),
        ['w1', 'w4', 'w7'],
      );
      expect(
        lexiconRowsForColumnGroup(
          rows: rows,
          groupIndex: 2,
          columnsCount: 3,
        ).map((r) => r['display_word']),
        ['w2', 'w5', 'w8'],
      );
    });

    test('returns empty for invalid group index', () {
      expect(
        lexiconRowsForColumnGroup(
          rows: rows,
          groupIndex: 3,
          columnsCount: 3,
        ),
        isEmpty,
      );
    });
  });
}
