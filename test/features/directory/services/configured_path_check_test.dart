// Έλεγχος ρυθμισμένων διαδρομών: ποιες από τις διαδρομές των ρυθμίσεων δεν
// υπάρχουν σε αυτό το μηχάνημα — ώστε η βάση που ταξιδεύει δουλειά ↔ σπίτι
// να μη «σέρνει» άκυρες διαδρομές που ανακαλύπτονται μία-μία.
//
//   flutter test test/features/directory/services/configured_path_check_test.dart

import 'dart:io';

import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/features/directory/screens/widgets/validation_rules_view.dart';
import 'package:call_logger/features/directory/services/configured_path_check.dart';
import 'package:call_logger/features/directory/services/configured_path_scan_result.dart';
import 'package:call_logger/features/directory/services/path_fix_destination.dart';
import 'package:call_logger/features/directory/services/path_fix_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

ConfiguredPathEntry _entry(String path, {bool inDb = true}) {
  return ConfiguredPathEntry(
    settingName: 'Δοκιμαστική ρύθμιση',
    path: path,
    storedInDatabase: inDb,
    fixDestination: PathFixDestination.updateFolder,
  );
}

void main() {
  group('evaluateConfiguredPaths', () {
    test('κρατά μόνο τις διαδρομές που δεν υπάρχουν', () async {
      final entries = [
        _entry(r'C:\ok\backups'),
        _entry(r'\\gnk.local\Departments\TPO\Backups'),
        _entry(r'C:\ok\tool.exe'),
      ];
      final invalid = await evaluateConfiguredPaths(
        entries,
        (path) async => path.startsWith(r'C:\ok'),
      );
      expect(invalid, hasLength(1));
      expect(invalid.single.path, r'\\gnk.local\Departments\TPO\Backups');
    });

    test('κενή διαδρομή = «χωρίς ρύθμιση», ποτέ εύρημα', () async {
      final invalid = await evaluateConfiguredPaths([
        _entry(''),
        _entry('   '),
      ], (_) async => false);
      expect(invalid, isEmpty);
    });

    test('όλα έγκυρα → κενή λίστα', () async {
      final invalid = await evaluateConfiguredPaths([
        _entry(r'C:\a'),
        _entry(r'C:\b', inDb: false),
      ], (_) async => true);
      expect(invalid, isEmpty);
    });
  });

  group('configuredPathExistsOnThisMachine', () {
    test('υπαρκτός φάκελος και υπαρκτό αρχείο → true', () async {
      final dir = await Directory.systemTemp.createTemp('path_check_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}x.txt');
      await file.writeAsString('x');

      expect(await configuredPathExistsOnThisMachine(dir.path), isTrue);
      expect(await configuredPathExistsOnThisMachine(file.path), isTrue);
    });

    test('ανύπαρκτη διαδρομή → false, χωρίς εξαίρεση', () async {
      expect(
        await configuredPathExistsOnThisMachine(
          r'C:\call_logger_test\δεν\υπάρχει\πουθενά',
        ),
        isFalse,
      );
    });
  });

  // Ο προορισμός διόρθωσης: το κουμπί «Μετάβαση στη ρύθμιση» και η οδηγία που
  // διαβάζει ο χρήστης πρέπει να λένε το ίδιο πράγμα, αλλιώς ο έλεγχος στέλνει
  // σε οθόνη που δεν φιλοξενεί τη ρύθμιση.
  group('προορισμός διόρθωσης', () {
    test('η οδηγία βγαίνει από τον προορισμό, όχι από δικό της κείμενο', () {
      final entry = ConfiguredPathEntry(
        settingName: 'Εργαλείο απομακρυσμένης «AnyDesk»',
        path: r'C:\Tools\AnyDesk.exe',
        storedInDatabase: true,
        fixDestination: PathFixDestination.remoteTools,
      );
      expect(entry.fixLocation, PathFixDestination.remoteTools.label);
    });

    test('τα απομακρυσμένα εργαλεία δείχνουν στο hub «Διάφορα»', () {
      // Δεν ζουν στις Ρυθμίσεις — εκεί δεν υπάρχει διαχείρισή τους.
      expect(PathFixDestination.remoteTools.label, contains('Διάφορα'));
      expect(
        PathFixDestination.remoteTools.label,
        contains('Απομακρυσμένα Εργαλεία'),
      );
      expect(
        PathFixDestination.remoteTools.label,
        isNot(contains('Ρυθμίσεις')),
      );
    });

    test('μόνο ο φάκελος ενημερώσεων απαιτεί δικαίωμα', () {
      final gated = PathFixDestination.values
          .where((d) => d.requiredPermission != null)
          .toList();
      expect(gated, [PathFixDestination.updateFolder]);
      expect(
        PathFixDestination.updateFolder.requiredPermission,
        AppPermission.manageUpdateFolder,
      );
    });
  });

  group('pathFixBlockedReason', () {
    test('χωρίς το δικαίωμα, η μετάβαση δεν προσφέρεται και λέει γιατί', () {
      final reason = pathFixBlockedReason(
        PathFixDestination.updateFolder,
        dictionaryNavVisible: true,
        can: (_) => false,
      );
      expect(reason, isNotNull);
      expect(reason, contains(AppPermission.manageUpdateFolder.label));
    });

    test('με το δικαίωμα, η μετάβαση προσφέρεται', () {
      expect(
        pathFixBlockedReason(
          PathFixDestination.updateFolder,
          dictionaryNavVisible: true,
          can: (_) => true,
        ),
        isNull,
      );
    });

    test('οι προορισμοί χωρίς δικαίωμα δεν ρωτούν καν την πύλη', () {
      var asked = false;
      final reason = pathFixBlockedReason(
        PathFixDestination.backupSettings,
        dictionaryNavVisible: true,
        can: (_) {
          asked = true;
          return false;
        },
      );
      expect(reason, isNull);
      expect(asked, isFalse);
    });

    // Χωρίς αυτό, το κουμπί θα ζητούσε οθόνη που ο χρήστης έχει κρύψει και
    // δεν θα άνοιγε τίποτα — σιωπηλά.
    test('κρυμμένο Λεξικό: οι διαδρομές του δεν υπόσχονται μετάβαση', () {
      final reason = pathFixBlockedReason(
        PathFixDestination.dictionaryPaths,
        dictionaryNavVisible: false,
      );
      expect(reason, isNotNull);
      expect(reason, contains('Λεξικό'));
    });

    test('κρυμμένο Λεξικό δεν εμποδίζει τους άλλους προορισμούς', () {
      expect(
        pathFixBlockedReason(
          PathFixDestination.remoteTools,
          dictionaryNavVisible: false,
        ),
        isNull,
      );
    });
  });

  // Το σενάριο: κοινόχρηστη βάση κλειδωμένη από συνάδελφο τη στιγμή του
  // ελέγχου. Οι ομάδες που ζουν ΜΕΣΑ στη βάση δεν διαβάζονται· ό,τι μένει
  // είναι οι τοπικές ρυθμίσεις, που βρίσκονται μια χαρά — και η οθόνη
  // ανακοίνωνε πράσινο «όλες οι διαδρομές βρέθηκαν».
  group('ομάδες που δεν διαβάστηκαν', () {
    test(
      'ομάδα που σκάει καταγράφεται ως ανεξέταστη, δεν εξαφανίζεται',
      () async {
        final inventory = await collectConfiguredPaths([
          ConfiguredPathGroup(
            name: 'τα εργαλεία απομακρυσμένης σύνδεσης',
            load: () async => throw StateError('database is locked'),
          ),
          ConfiguredPathGroup(
            name: 'οι τοπικές ρυθμίσεις',
            load: () async => [_entry(r'C:\ok\updates')],
          ),
        ]);

        expect(inventory.unreadableGroups, [
          'τα εργαλεία απομακρυσμένης σύνδεσης',
        ]);
        expect(inventory.entries, hasLength(1));
      },
    );

    test('όλες οι ομάδες διαβάστηκαν → καμία ανεξέταστη', () async {
      final inventory = await collectConfiguredPaths([
        ConfiguredPathGroup(name: 'α', load: () async => [_entry(r'C:\a')]),
        ConfiguredPathGroup(name: 'β', load: () async => [_entry(r'C:\b')]),
      ]);

      expect(inventory.unreadableGroups, isEmpty);
      expect(inventory.entries, hasLength(2));
    });

    test('μία ομάδα που σκάει δεν παρασύρει τις υπόλοιπες', () async {
      final inventory = await collectConfiguredPaths([
        ConfiguredPathGroup(name: 'α', load: () async => [_entry(r'C:\a')]),
        ConfiguredPathGroup(
          name: 'β',
          load: () async => throw StateError('boom'),
        ),
        ConfiguredPathGroup(name: 'γ', load: () async => [_entry(r'C:\c')]),
      ]);

      expect(inventory.unreadableGroups, ['β']);
      expect(inventory.entries, hasLength(2));
    });
  });

  // Η καρδιά του σφάλματος: το αποτέλεσμα του ελέγχου δεν μπορούσε καν να
  // εκφράσει το «δεν εξέτασα» — μηδέν ευρήματα σήμαινε πάντα «όλα καθαρά».
  group('αποτέλεσμα ελέγχου διαδρομών', () {
    test('ανεξέταστη ομάδα: το αποτέλεσμα ΔΕΝ δηλώνεται πλήρες', () {
      const result = ConfiguredPathScanResult(
        invalidPaths: [],
        uncheckedGroups: ['τα εργαλεία απομακρυσμένης σύνδεσης'],
      );
      expect(result.isFullyChecked, isFalse);
    });

    test('καμία ανεξέταστη ομάδα και κανένα εύρημα: πλήρες και καθαρό', () {
      const result = ConfiguredPathScanResult(
        invalidPaths: [],
        uncheckedGroups: [],
      );
      expect(result.isFullyChecked, isTrue);
    });
  });

  // Άκρη-σε-άκρη στην ΠΡΑΓΜΑΤΙΚΗ συνάρτηση που καλεί η οθόνη — όχι μόνο στον
  // βοηθό της: εκεί χανόταν η πληροφορία πριν.
  group('findInvalidConfiguredPaths', () {
    test('ομάδα που δεν διαβάστηκε φτάνει ως το αποτέλεσμα', () async {
      final result = await findInvalidConfiguredPaths(
        groups: [
          ConfiguredPathGroup(
            name: 'τα εργαλεία απομακρυσμένης σύνδεσης',
            load: () async => throw StateError('database is locked'),
          ),
          ConfiguredPathGroup(
            name: 'οι τοπικές διαδρομές',
            load: () async => [_entry(r'C:\ok\updates')],
          ),
        ],
        pathExists: (_) async => true,
      );

      // Καμία άκυρη διαδρομή — αλλά ο έλεγχος ΔΕΝ ήταν πλήρης.
      expect(result.invalidPaths, isEmpty);
      expect(result.isFullyChecked, isFalse);
      expect(result.uncheckedGroups, ['τα εργαλεία απομακρυσμένης σύνδεσης']);
    });

    test('όλα διαβάστηκαν και όλα βρέθηκαν → πλήρης και καθαρός', () async {
      final result = await findInvalidConfiguredPaths(
        groups: [
          ConfiguredPathGroup(
            name: 'οι τοπικές διαδρομές',
            load: () async => [_entry(r'C:\ok\updates')],
          ),
        ],
        pathExists: (_) async => true,
      );

      expect(result.invalidPaths, isEmpty);
      expect(result.isFullyChecked, isTrue);
    });
  });

  // Η υπόσχεση που διαβάζει ο χρήστης: «όλες» μόνο όταν εξετάστηκαν όλες.
  group('μήνυμα καθαρού αποτελέσματος', () {
    test('πλήρης έλεγχος: μιλά για ΟΛΕΣ τις διαδρομές', () {
      expect(configuredPathsCleanMessage(partial: false), contains('Όλες'));
    });

    test('ατελής έλεγχος: ΔΕΝ μιλά για όλες', () {
      final message = configuredPathsCleanMessage(partial: true);
      expect(message, contains('υπόλοιπες'));
      expect(message, isNot(contains('Όλες')));
    });
  });
}
