// Η αναζήτηση του Καταλόγου βρίσκει και με αναγνωριστικό Lansweeper — χωρίς
// να χρειάζεται ο τομέας μπροστά.
//
//   flutter test test/features/directory/catalog_lansweeper_search_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kUserIdentifier = r'gnk\e.plakogianni';
const _kDepartmentName = 'Παθολογική';
const _kDepartmentAccounts =
    r'[{"username":"gnk\\docpath1","label":"Γιατρός Παθολογικής 1"},'
    r'{"username":"gnk\\docpath2","label":"Γιατρός Παθολογικής 2"}]';

/// Εξοπλισμός χωρίς γραμμένο αναγνωριστικό — η συνηθισμένη περίπτωση: και τα
/// 112 κομμάτια της βάσης του νοσοκομείου είναι έτσι σήμερα. Στο Lansweeper
/// ταξιδεύει ως «PC» + κωδικός.
const _kAutoNamedCode = '3184';
const _kAutoNamedAsset = 'PC3184';

/// Εξοπλισμός με δικό του αναγνωριστικό, που κερδίζει τον αυτόματο κανόνα.
const _kStoredNameCode = '4021';
const _kStoredAssetName = 'LAB-SCANNER-01';

Future<void> _seedLansweeperRecords() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('users', where: 'last_name = ?', whereArgs: ['Πλακογιάννη']);
  await db.delete(
    'departments',
    where: 'name = ?',
    whereArgs: [_kDepartmentName],
  );
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

/// Δύο κομμάτια εξοπλισμού που καλύπτουν και τις δύο περιπτώσεις: το ένα με
/// γραμμένο αναγνωριστικό, το άλλο χωρίς.
Future<void> _seedLansweeperEquipment() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete(
    'equipment',
    where: 'code_equipment IN (?, ?)',
    whereArgs: [_kAutoNamedCode, _kStoredNameCode],
  );
  await db.insert('equipment', {
    'code_equipment': _kAutoNamedCode,
    'type': 'Υπολογιστής',
    'lansweeper_asset_name': null,
    'is_deleted': 0,
  });
  await db.insert('equipment', {
    'code_equipment': _kStoredNameCode,
    'type': 'Υπολογιστής',
    'lansweeper_asset_name': _kStoredAssetName,
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

      expect(
        summary.hiddenMatchCounts.keys,
        contains('Αναγνωριστικό Lansweeper'),
      );
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
      final found = container
          .read(departmentDirectoryProvider)
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
      final found = container
          .read(departmentDirectoryProvider)
          .filteredDepartments;

      expect(found.map((d) => d.name), contains(_kDepartmentName));
    });

    test('εξοπλισμός: το «PC3184» βρίσκει τον κωδικό 3184', () async {
      // Το πεδίο είναι κενό — όπως σε ΟΛΑ τα κομμάτια της βάσης σήμερα. Αυτό
      // που φεύγει προς το Lansweeper είναι το αυτόματο «PC» + κωδικός, και
      // αυτό ακριβώς θυμάται ο χρήστης όταν κοιτάζει ένα ticket.
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await _seedLansweeperEquipment();
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(equipmentDirectoryProvider.notifier);
      await notifier.load();

      notifier.setSearchQuery(_kAutoNamedAsset);
      final found = container.read(equipmentDirectoryProvider).filteredItems;

      expect(
        found.map((row) => row.$1.code),
        contains(_kAutoNamedCode),
        reason: greekExpectMsg(
          'Αν η αναζήτηση κοίταζε μόνο το αποθηκευμένο πεδίο, δεν θα έβρισκε '
          'κανένα κομμάτι — όλα το έχουν κενό',
        ),
      );
    });

    test('εξοπλισμός: το γραμμένο αναγνωριστικό κερδίζει', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await _seedLansweeperEquipment();
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(equipmentDirectoryProvider.notifier);
      await notifier.load();

      notifier.setSearchQuery('scanner');
      final found = container.read(equipmentDirectoryProvider).filteredItems;

      expect(
        found.map((row) => row.$1.code),
        contains(_kStoredNameCode),
        reason: greekExpectMsg(
          'Όποιος γράψει δικό του αναγνωριστικό πρέπει να το βρίσκει με αυτό',
        ),
      );
    });

    test('εξοπλισμός: ο αυτόματος κανόνας ΔΕΝ σκεπάζει το γραμμένο', () async {
      // Ο κωδικός 4021 έχει δικό του όνομα· το «PC4021» δεν ταξιδεύει πουθενά
      // και δεν πρέπει να βρίσκει τίποτα.
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await _seedLansweeperEquipment();
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(equipmentDirectoryProvider.notifier);
      await notifier.load();

      notifier.setSearchQuery('PC4021');
      final found = container.read(equipmentDirectoryProvider).filteredItems;

      expect(found.map((row) => row.$1.code), isNot(contains(_kStoredNameCode)));
    });

    test('εξοπλισμός: το εύρημα δηλώνεται ως κρυφό πεδίο', () async {
      // Δεν υπάρχει στήλη «Αναγνωριστικό Lansweeper» στον πίνακα εξοπλισμού,
      // οπότε η γραμμή ταιριάζει χωρίς τίποτα ορατό να το εξηγεί.
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);

      await _seedLansweeperEquipment();
      await container.read(lookupServiceProvider.future);
      final notifier = container.read(equipmentDirectoryProvider.notifier);
      await notifier.load();

      notifier.setSearchQuery(_kAutoNamedAsset);
      final summary = container.read(equipmentDirectoryProvider).searchSummary;

      expect(
        summary.hiddenMatchCounts.keys,
        contains('Αναγνωριστικό Lansweeper'),
        reason: greekExpectMsg(
          'Ίδια ετικέτα με τη φόρμα εξοπλισμού και με τους Υπαλλήλους',
        ),
      );
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
