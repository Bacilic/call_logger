import 'package:call_logger/core/database/old_database/lamp_table_greek_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lampTableDisplayGreek', () {
    test('search_index εμφανίζεται ως Ευρετηρίαση', () {
      expect(
        lampTableDisplayGreek('search_index'),
        'Ευρετηρίαση (search_index)',
      );
    });
  });

  group('lampOrderedTableNames', () {
    test('πίνακες δεδομένων πρώτα, άγνωστοι αλφαβητικά, τεχνικοί τελευταίοι', () {
      final ordered = lampOrderedTableNames(<String>[
        'search_index',
        'equipment',
        'meta',
        'data_issues',
        'contracts',
        'model',
        'owners',
        'offices',
        'import_log',
        'etl_run',
      ]);

      expect(ordered, <String>[
        'equipment',
        'offices',
        'owners',
        'model',
        'contracts',
        'etl_run',
        'import_log',
        'meta',
        'data_issues',
        'search_index',
      ]);
    });

    test('data_issues πριν από search_index στους τεχνικούς πίνακες', () {
      final ordered = lampOrderedTableNames(<String>[
        'search_index',
        'data_issues',
      ]);

      expect(ordered, <String>['data_issues', 'search_index']);
    });
  });
}
