// Κάθε πίνακας που βλέπει ο χρήστης στη «Βάση Δεδομένων» έχει ελληνικό όνομα.
// Η λίστα διαβάζεται από την πραγματική βάση, όχι από χειρόγραφο αντίγραφο:
// πίνακας που προστίθεται στο σχήμα χωρίς όνομα κοκκινίζει εδώ αμέσως.
//
//   flutter test test/core/database/database_table_labels_schema_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_table_labels.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  test('κάθε πίνακας της βάσης έχει ελληνικό όνομα', () async {
    final tables = await DatabaseHelper.instance.tableInspection
        .getTableNames();
    expect(tables, isNotEmpty);

    final untranslated = [
      for (final t in tables)
        if (databaseTableLabelEl(t) == t) t,
    ];

    expect(untranslated, isEmpty);
  });
}
