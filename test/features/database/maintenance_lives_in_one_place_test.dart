// Η συντήρηση της βάσης ζει σε ΕΝΑ σπίτι, και η δημιουργία βάσης σε άλλο.
//
// Το συμβόλαιο: «Κάθε εργαλείο συντήρησης της βάσης ζει στην καρτέλα
// Συντήρηση των Ρυθμίσεων — και μόνο εκεί· η δημιουργία/εναλλαγή αρχείων
// ανήκει στην καρτέλα Βάση.»
//
// Πριν: η καρτέλα «Συντήρηση» είχε μόνο τον έλεγχο ακεραιότητας, ενώ η
// πραγματική συντήρηση (VACUUM, αναδόμηση ευρετηρίων, εκκαθάριση) ζούσε σε
// ξεχωριστό διάλογο αλλού — και είχε μέσα και δεύτερο κουμπί «Δημιουργία νέας
// βάσης», μη αναστρέψιμη ενέργεια με δύο δρόμους προς αυτήν.
//
// Έλεγχος πηγαίου κώδικα και όχι widget: το ζητούμενο είναι «πού ζει το
// καθένα», δηλαδή δομή του έργου — όχι συμπεριφορά μιας οθόνης.
//
//   flutter test test/features/database/maintenance_lives_in_one_place_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _file(String relative) => File(
  '${Directory.current.path}${Platform.pathSeparator}'
  '${relative.replaceAll('/', Platform.pathSeparator)}',
);

const _maintenanceTab =
    'lib/features/database/widgets/database_settings_maintenance_tab.dart';
const _sections =
    'lib/features/database/widgets/database_maintenance_sections.dart';
const _browser = 'lib/features/database/screens/database_browser_screen.dart';
const _integrityDialogs =
    'lib/features/database/widgets/integrity_fix_dialogs.dart';

void main() {
  test('η καρτέλα «Συντήρηση» φιλοξενεί τις εργασίες συντήρησης', () {
    final tab = _file(_maintenanceTab).readAsStringSync();

    expect(tab, contains('DatabaseMaintenanceSections'));
    expect(
      tab,
      contains('AppPermission.databaseMaintenance'),
      reason:
          'Οι βαριές εργασίες θέλουν το δικαίωμα· ο έλεγχος ήταν μόνο στα '
          'κουμπιά που άνοιγαν τον παλιό διάλογο.',
    );
  });

  test('οι εργασίες συντήρησης δεν είναι πια ξεχωριστός διάλογος', () {
    final sections = _file(_sections).readAsStringSync();

    expect(
      sections,
      isNot(
        contains(
          'showDialog<void>(\n      context: context,\n      '
          'barrierDismissible: false,\n      builder: (ctx) =>\n          '
          'DatabaseMaintenancePanel',
        ),
      ),
    );
    expect(
      sections.contains('class DatabaseMaintenanceSections'),
      isTrue,
      reason: 'Ενσωματώνεται στην καρτέλα αντί να ανοίγει μόνο του.',
    );
  });

  test('η «Δημιουργία νέας βάσης» έφυγε από τη συντήρηση', () {
    final sections = _file(_sections).readAsStringSync();

    expect(
      sections,
      isNot(contains('CreateNewDatabaseFlow')),
      reason: 'Η δημιουργία αρχείων ανήκει στην καρτέλα «Βάση».',
    );
    expect(sections, isNot(contains('Δημιουργία νέας βάσης')));
  });

  test('η δημιουργία βάσης παραμένει στην καρτέλα «Βάση»', () {
    final fileTab = _file(
      'lib/features/database/widgets/database_settings_file_tab.dart',
    ).readAsStringSync();

    expect(fileTab, contains('CreateNewDatabaseFlow.run'));
  });

  test('δεν έμεινε δεύτερη πόρτα προς τη συντήρηση', () {
    for (final path in [_browser, _integrityDialogs]) {
      expect(
        _file(path).readAsStringSync(),
        isNot(contains('DatabaseMaintenancePanel')),
        reason: '$path άνοιγε τον παλιό διάλογο.',
      );
    }
  });

  test(
    'ο έλεγχος ακεραιότητας δεν υπόσχεται κουμπί που δεν οδηγεί πουθενά',
    () {
      // Το κουμπί «Συντήρηση βάσης» εξαρτιόταν από callback που ο μοναδικός
      // καλών δεν περνούσε ποτέ — δηλαδή έκλεινε τον διάλογο και τίποτε άλλο.
      final dialogs = _file(_integrityDialogs).readAsStringSync();

      expect(dialogs, isNot(contains("Text('Συντήρηση βάσης')")));
      expect(dialogs, isNot(contains('onDatabaseReopened')));
    },
  );
}
