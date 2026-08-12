// Η αναζήτηση του Καταλόγου βρίσκει και με αναγνωριστικό Lansweeper — χωρίς
// να χρειάζεται ο τομέας μπροστά.
//
//   flutter test test/features/directory/catalog_lansweeper_search_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kUserIdentifier = r'gnk\e.plakogianni';
const _kDepartmentName = 'Παθολογική';
const _kDepartmentAccounts =
    r'[{"username":"gnk\\docpath1","label":"Γιατρός Παθολογικής 1"},'
    r'{"username":"gnk\\docpath2","label":"Γιατρός Παθολογικής 2"}]';

Future<void> _seedLansweeperRecords() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('users', where: 'last_name = ?', whereArgs: ['Πλακογιάννη']);
  await db.delete('departments', where: 'name = ?', whereArgs: [
    _kDepartmentName,
  ]);
  await db.insert('users', {
    'first_name': 'Ελένη',
    'last_name': 'Πλακογιάννη',
    'lansweeper_username': _kUserIdentifier,
    'is_deleted': 0,
  });
  await db.insert('departments', {
    'name': _kDepartmentName,
    // Υποχρεωτικό κλειδί ταυτότητας του πίνακα — παράγεται με τον ίδιο
    // κανονικοποιητή που χρησιμοποιεί το repository.
    'name_key': SearchTextNormalizer.normalizeForSearch(_kDepartmentName),
    'lansweeper_usernames': _kDepartmentAccounts,
    'is_deleted': 0,
  });
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Αναζήτηση Καταλόγου με αναγνωριστικό Lansweeper', () {
    test('υπάλληλος: το «plakogianni» τον βρίσκει χωρίς τον τομέα', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await _seedLansweeperRecords();
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(directoryProvider.notifier);
      await notifier.loadUsers();

      notifier.setSearchQuery('plakogianni');
      final found = container.read(directoryProvider).filteredUsers;

      expect(
        found.map((u) => u.lastName),
        contains('Πλακογιάννη'),
        reason: greekExpectMsg(
          'Το αναγνωριστικό είναι «$_kUserIdentifier» — η αναζήτηση οφείλει '
          'να το βρίσκει και χωρίς το «gnk\\» μπροστά',
        ),
      );
    });

    test('υπάλληλος: το εύρημα δηλώνεται ως κρυφό πεδίο', () async {
      // Δεν υπάρχει στήλη «Αναγνωριστικό Lansweeper» στον πίνακα, οπότε η
      // εγγραφή ταιριάζει χωρίς τίποτα ορατό να το εξηγεί. Η γραμμή
      // αποτελεσμάτων πρέπει να το λέει, αλλιώς μοιάζει σφάλμα.
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await _seedLansweeperRecords();
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(directoryProvider.notifier);
      await notifier.loadUsers();

      notifier.setSearchQuery('plakogianni');
      final summary = container.read(directoryProvider).searchSummary;

      expect(summary.hiddenMatchCounts.keys, contains('Αναγνωριστικό Lansweeper'));
    });

    test('τμήμα: το «docpath» φέρνει την Παθολογική', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await _seedLansweeperRecords();
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(departmentDirectoryProvider.notifier);
      await notifier.loadDepartments();

      notifier.setSearchQuery('docpath');
      final found = container.read(departmentDirectoryProvider)
          .filteredDepartments;

      expect(
        found.map((d) => d.name),
        contains(_kDepartmentName),
        reason: greekExpectMsg(
          'Τα αναγνωριστικά είναι «gnk\\docpath1/2» — το σκέτο «docpath» '
          'οφείλει να φτάνει',
        ),
      );
    });

    test('τμήμα: βρίσκεται και από την ονομασία του λογαριασμού', () async {
      // Η ονομασία πριν το «=» μένει στην εφαρμογή και δεν φεύγει ποτέ στο
      // Lansweeper — είναι όμως ό,τι θυμάται ο χρήστης.
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await _seedLansweeperRecords();
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(departmentDirectoryProvider.notifier);
      await notifier.loadDepartments();

      notifier.setSearchQuery('Γιατρός Παθολογικής 2');
      final found = container.read(departmentDirectoryProvider)
          .filteredDepartments;

      expect(found.map((d) => d.name), contains(_kDepartmentName));
    });

    test('άσχετο ερώτημα δεν φέρνει τίποτα από τα νέα πεδία', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await _seedLansweeperRecords();
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(departmentDirectoryProvider.notifier);
      await notifier.loadDepartments();

      notifier.setSearchQuery('ανύπαρκτοσλογαριασμοσ');

      expect(
        container.read(departmentDirectoryProvider).filteredDepartments,
        isEmpty,
      );
    });
  });
}
