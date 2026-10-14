// Ο κατάλογος πινάκων της οθόνης «Βάση Δεδομένων»: ελληνικά ονόματα και
// σειρά όπως η πλευρική μπάρα.
//
//   flutter test test/features/database/database_table_catalog_test.dart

import 'package:call_logger/features/database/models/database_table_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('οι γνωστοί πίνακες με τη σειρά της μπάρας, οι άγνωστοι μετά, '
      'αλφαβητικά', () {
    const raw = [
      'users',
      'zeta_unknown',
      'app_settings',
      'calls',
      'operators',
      'tasks',
      'alpha_unknown',
      'full_dictionary',
      'categories',
    ];

    expect(orderDatabaseTableNames(raw), [
      'calls',
      'categories',
      'tasks',
      'users',
      'app_settings',
      'full_dictionary',
      'alpha_unknown',
      'operators',
      'zeta_unknown',
    ]);
  });

  test('ελληνικό όνομα όπου υπάρχει, αλλιώς το όνομα του πίνακα', () {
    expect(databaseTableDisplayName('calls'), 'Κλήσεις');
    expect(databaseTableDisplayName('audit_log'), 'Αρχείο καταγραφής (audit)');
    expect(
      databaseTableDisplayName('user_phones'),
      'Συσχέτιση χρήστη–τηλεφώνου',
    );
    expect(databaseTableDisplayName('operators'), 'operators');
  });
}
