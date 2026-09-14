// Ο οδηγός επαναφοράς: ο χρήστης επιλέγει ΤΙ θα επαναφερθεί, και η επιλογή
// του φτάνει ακέραιη στον καλούντα. Ελέγχεται συμπεριφορά — τι επιστρέφεται,
// τι ζητά δεύτερη επιβεβαίωση, τι δεν επιτρέπεται — όχι εμφάνιση.
//
//   flutter test test/features/database/widgets/restore_from_backup_dialog_test.dart --timeout 30s

import 'package:call_logger/core/config/app_config.dart';
import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_integrity_probe.dart';
import 'package:call_logger/core/database/database_schema_version.dart';
import 'package:call_logger/core/services/building_map_storage.dart';
import 'package:call_logger/features/database/services/backup_zip_inventory.dart';
import 'package:call_logger/features/database/services/backup_zip_manifest.dart';
import 'package:call_logger/features/database/services/restore_plan.dart';
import 'package:call_logger/features/database/services/restore_selection.dart';
import 'package:call_logger/features/database/widgets/restore_from_backup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _backupProfile = DatabaseFileProfile(
  kind: DatabaseFileKind.callLogger,
  callCount: 496,
  userCount: 102,
  latestCallDate: '2026-09-04',
);

const _currentProfile = DatabaseFileProfile(
  kind: DatabaseFileKind.callLogger,
  callCount: 500,
  userCount: 102,
  latestCallDate: '2026-09-12',
);

/// Πλήρες αντίγραφο: κατόψεις, εικονίδια, λεξικό και βάση Λάμπας.
const _fullPresence = BackupZipPortablePresence(
  hasManifest: true,
  mapsCount: 14,
  imagesCount: 31,
  dictionariesCount: 2,
  lampDatabaseCount: 1,
);

Future<RestoreSelection?> _open(
  WidgetTester tester, {
  BackupZipPortablePresence presence = _fullPresence,
  bool allowSkippingDatabase = true,
  DateTime? localLampDatabaseModified,
  DatabaseFileProfile backupProfile = _backupProfile,
  DatabaseFileProfile? currentProfile = _currentProfile,
  LocalPortableCounts localCounts = const LocalPortableCounts(),
}) async {
  RestoreSelection? captured;
  var closed = false;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showRestoreFromBackupDialog(
                  context: context,
                  currentProfile: currentProfile,
                  backupProfile: backupProfile,
                  manifest: const BackupZipManifest.unknown(),
                  currentDatabasePath: r'C:\data\Hospital.db',
                  availableDestinations: const [
                    RestoreDestinationChoice.currentDatabase,
                    RestoreDestinationChoice.backupName,
                  ],
                  portablePresence: presence,
                  preferredDatabaseFileName: 'call_logger.db',
                  allowSkippingDatabase: allowSkippingDatabase,
                  localLampDatabaseModified: localLampDatabaseModified,
                  localCounts: localCounts,
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(closed, isFalse, reason: 'Ο διάλογος πρέπει να είναι ανοιχτός');
  return captured;
}

/// Το κουτάκι της γραμμής με τον δοσμένο τίτλο.
Finder _checkboxOf(String title) => find.ancestor(
  of: find.text(title),
  matching: find.byType(CheckboxListTile),
);

bool _isChecked(WidgetTester tester, String title) =>
    tester.widget<CheckboxListTile>(_checkboxOf(title)).value ?? false;

bool _isEnabled(WidgetTester tester, String title) =>
    tester.widget<CheckboxListTile>(_checkboxOf(title)).onChanged != null;

void main() {
  testWidgets('προεπιλογή: έρχονται όσα υπάρχουν στο αντίγραφο', (
    tester,
  ) async {
    await _open(tester);
    for (final title in [
      'Βάση δεδομένων',
      'Κατόψεις κτιρίων',
      'Εικονίδια εργαλείων και χρηστών',
      'Λεξικό',
      'Βάση Λάμπας',
    ]) {
      expect(_isChecked(tester, title), isTrue, reason: title);
    }
  });

  testWidgets('στοιχείο που λείπει από το αντίγραφο δεν επιλέγεται', (
    tester,
  ) async {
    await _open(
      tester,
      presence: const BackupZipPortablePresence(
        hasManifest: true,
        mapsCount: 14,
      ),
    );
    expect(_isChecked(tester, 'Κατόψεις κτιρίων'), isTrue);
    expect(_isEnabled(tester, 'Λεξικό'), isFalse);
    expect(_isChecked(tester, 'Λεξικό'), isFalse);
    expect(find.text('Δεν υπάρχει σε αυτό το αντίγραφο'), findsWidgets);
  });

  testWidgets(
    'νεότερη τοπική βάση Λάμπας ξεκινά ξετσεκάριστη — η επαναφορά θα έσβηνε δουλειά',
    (tester) async {
      await _open(
        tester,
        presence: BackupZipPortablePresence(
          hasManifest: true,
          mapsCount: 2,
          lampDatabaseCount: 1,
          lampDatabaseModified: DateTime(2026, 9, 2),
        ),
        localLampDatabaseModified: DateTime(2026, 9, 7),
      );
      expect(_isChecked(tester, 'Βάση Λάμπας'), isFalse);
      expect(_isEnabled(tester, 'Βάση Λάμπας'), isTrue);
      expect(_isChecked(tester, 'Κατόψεις κτιρίων'), isTrue);
    },
  );

  testWidgets('η επιλογή του χρήστη φτάνει ακέραιη στον καλούντα', (
    tester,
  ) async {
    RestoreSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showRestoreFromBackupDialog(
                    context: context,
                    currentProfile: _currentProfile,
                    backupProfile: _backupProfile,
                    manifest: const BackupZipManifest.unknown(),
                    currentDatabasePath: r'C:\data\Hospital.db',
                    availableDestinations: const [
                      RestoreDestinationChoice.currentDatabase,
                    ],
                    portablePresence: _fullPresence,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Λεξικό'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Βάση Λάμπας'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Επαναφορά 3 στοιχείων'),
    );
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.restoresDatabase, isTrue);
    expect(result!.parts, {
      RestorePortablePart.maps,
      RestorePortablePart.toolImages,
    });
  });

  testWidgets(
    'ξετσεκάρισμα της βάσης ζητά δεύτερη επιβεβαίωση — το «Πίσω» δεν κλείνει τίποτα',
    (tester) async {
      await _open(tester);
      await tester.tap(find.text('Βάση δεδομένων'));
      await tester.pumpAndSettle();
      expect(_isChecked(tester, 'Βάση δεδομένων'), isFalse);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Επαναφορά 4 στοιχείων'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Χωρίς επαναφορά της βάσης;'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Πίσω'));
      await tester.pumpAndSettle();
      expect(find.text('Χωρίς επαναφορά της βάσης;'), findsNothing);
      expect(find.text('Επαναφορά από αντίγραφο'), findsOneWidget);
    },
  );

  testWidgets(
    'όταν η βάση δεν επαναφέρεται, δεν ζητείται όνομα και η επιλογή δεν έχει προορισμό',
    (tester) async {
      RestoreSelection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showRestoreFromBackupDialog(
                      context: context,
                      currentProfile: _currentProfile,
                      backupProfile: _backupProfile,
                      manifest: const BackupZipManifest.unknown(),
                      currentDatabasePath: r'C:\data\Hospital.db',
                      availableDestinations: const [
                        RestoreDestinationChoice.currentDatabase,
                      ],
                      portablePresence: _fullPresence,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Με ποιο όνομα να γίνει η επαναφορά;'), findsOneWidget);
      await tester.tap(find.text('Βάση δεδομένων'));
      await tester.pumpAndSettle();
      expect(find.text('Με ποιο όνομα να γίνει η επαναφορά;'), findsNothing);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Επαναφορά 4 στοιχείων'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Συνέχεια'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.restoresDatabase, isFalse);
      expect(result!.destination, isNull);
      expect(result!.parts.length, 4);
    },
  );

  testWidgets(
    'όπου η βάση είναι υποχρεωτική, το κουτάκι της δεν ξετσεκάρεται',
    (tester) async {
      await _open(tester, allowSkippingDatabase: false);
      expect(_isEnabled(tester, 'Βάση δεδομένων (πάντα)'), isFalse);
      expect(_isChecked(tester, 'Βάση δεδομένων (πάντα)'), isTrue);
    },
  );

  testWidgets('χωρίς κανένα επιλεγμένο στοιχείο, η επαναφορά δεν προσφέρεται', (
    tester,
  ) async {
    await _open(
      tester,
      presence: const BackupZipPortablePresence(hasManifest: true),
    );
    await tester.tap(find.text('Βάση δεδομένων'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Επαναφορά'),
    );
    expect(button.onPressed, isNull);
  });

  group('αντίγραφο από νεότερη έκδοση της εφαρμογής', () {
    // Το σχήμα είναι πλήρες και το περιεχόμενο υγιές — ό,τι έκρινε ο κριτής
    // μέχρι πρότινος έλεγε «ναι». Η άρνηση οφείλει να έρθει ΕΔΩ, στον
    // διάλογο: ένα βήμα αργότερα η ενεργή βάση έχει ήδη αντικατασταθεί.
    final fromTheFuture = DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      userVersion: kDatabaseSchemaVersion + 39,
      callCount: 496,
      userCount: 102,
      latestCallDate: '2026-09-04',
    );

    testWidgets('το κουτάκι της βάσης είναι κλειδωμένο ΚΛΕΙΣΤΟ', (
      tester,
    ) async {
      await _open(tester, backupProfile: fromTheFuture);
      const title = 'Βάση δεδομένων — δεν επαναφέρεται';
      expect(_isChecked(tester, title), isFalse);
      expect(_isEnabled(tester, title), isFalse);
    });

    testWidgets('η αιτία λέει ότι χρειάζεται νεότερη εγκατάσταση', (
      tester,
    ) async {
      await _open(tester, backupProfile: fromTheFuture);
      expect(find.textContaining('νεότερη εγκατάσταση'), findsOneWidget);
      expect(
        find.textContaining('${kDatabaseSchemaVersion + 39}'),
        findsWidgets,
      );
    });
  });

  group('ασύμβατη βάση δεν επαναφέρεται με τίποτα', () {
    const incomplete = DatabaseFileProfile(
      kind: DatabaseFileKind.incompleteCallLogger,
      missingCoreTables: ['phones', 'departments'],
      userVersion: 1,
    );

    testWidgets(
      'το κουτάκι της είναι κλειδωμένο ΚΛΕΙΣΤΟ και λέει ποιοι πίνακες λείπουν',
      (tester) async {
        await _open(tester, backupProfile: incomplete);
        const title = 'Βάση δεδομένων — δεν επαναφέρεται';
        expect(_isChecked(tester, title), isFalse);
        expect(_isEnabled(tester, title), isFalse);
        expect(find.textContaining('phones'), findsOneWidget);
        expect(find.textContaining('departments'), findsOneWidget);
      },
    );

    testWidgets('τα υπόλοιπα στοιχεία του αντιγράφου παραμένουν διαθέσιμα', (
      tester,
    ) async {
      await _open(tester, backupProfile: incomplete);
      expect(_isChecked(tester, 'Κατόψεις κτιρίων'), isTrue);
      expect(
        find.widgetWithText(FilledButton, 'Επαναφορά 4 στοιχείων'),
        findsOneWidget,
      );
    });

    testWidgets(
      'ούτε εκεί που η βάση είναι υποχρεωτική δεν ξεκλειδώνει — δεν προσφέρεται επαναφορά',
      (tester) async {
        await _open(
          tester,
          backupProfile: incomplete,
          allowSkippingDatabase: false,
          presence: const BackupZipPortablePresence(hasManifest: true),
        );
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Επαναφορά'),
        );
        expect(button.onPressed, isNull);
      },
    );
  });

  group('η απώλεια δεδομένων λέγεται πριν γίνει', () {
    testWidgets(
      'αντίγραφο με λιγότερες εγγραφές το δηλώνει στη γραμμή της βάσης',
      (tester) async {
        await _open(
          tester,
          backupProfile: const DatabaseFileProfile(
            kind: DatabaseFileKind.callLogger,
            callCount: 186,
            userCount: 107,
            equipmentCount: 130,
          ),
          currentProfile: const DatabaseFileProfile(
            kind: DatabaseFileKind.callLogger,
            callCount: 496,
            userCount: 102,
            equipmentCount: 113,
          ),
        );
        expect(find.textContaining('θα χαθούν 310 κλήσεις'), findsOneWidget);
      },
    );

    testWidgets('αντίγραφο με περισσότερες εγγραφές δεν προειδοποιεί', (
      tester,
    ) async {
      await _open(
        tester,
        backupProfile: const DatabaseFileProfile(
          kind: DatabaseFileKind.callLogger,
          callCount: 600,
        ),
        currentProfile: const DatabaseFileProfile(
          kind: DatabaseFileKind.callLogger,
          callCount: 496,
        ),
      );
      expect(find.textContaining('θα χαθούν'), findsNothing);
    });

    testWidgets('λιγότερες κατόψεις από όσες έχετε: το λέει με τα δύο πλήθη', (
      tester,
    ) async {
      await _open(
        tester,
        presence: const BackupZipPortablePresence(
          hasManifest: true,
          mapsCount: 1,
          imagesCount: 31,
        ),
        localCounts: const LocalPortableCounts(maps: 14, toolImages: 31),
      );
      expect(
        find.textContaining('έχετε 14, θα μείνουν 1'),
        findsOneWidget,
        reason:
            'Η απώλεια κατόψεων είναι αθόρυβη — τα αρχεία μένουν, η '
            'βάση δεν τα ξέρει',
      );
      expect(
        find.textContaining('έχετε 31'),
        findsNothing,
        reason: 'Ίδιο πλήθος δεν είναι απώλεια',
      );
    });

    testWidgets('χωρίς τοπικά αρχεία, καμία προειδοποίηση απώλειας', (
      tester,
    ) async {
      await _open(tester, localCounts: const LocalPortableCounts());
      expect(find.textContaining('θα μείνουν'), findsNothing);
    });
  });

  testWidgets('η έκδοση σχήματος φαίνεται δίπλα σε κάθε πλευρά της σύγκρισης', (
    tester,
  ) async {
    await _open(
      tester,
      backupProfile: const DatabaseFileProfile(
        kind: DatabaseFileKind.callLogger,
        userVersion: 17,
      ),
      currentProfile: const DatabaseFileProfile(
        kind: DatabaseFileKind.callLogger,
        userVersion: 59,
      ),
    );
    expect(find.text('Τρέχουσα (έκδ. 59)'), findsOneWidget);
    expect(find.text('Αντίγραφο (έκδ. 17)'), findsOneWidget);
  });

  testWidgets('άγνωστη έκδοση δεν γεμίζει την κεφαλίδα με μηδενικά', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Τρέχουσα'), findsOneWidget);
    expect(find.text('Αντίγραφο'), findsOneWidget);
  });

  testWidgets('τα ονόματα φακέλων του αντιγράφου δεν διαρρέουν στη διεπαφή', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text(BuildingMapStorage.backupZipMapsFolderName), findsNothing);
    expect(find.text(AppConfig.portableImagesDirName), findsNothing);
  });

  // Η φθαρμένη βάση είναι η ΤΡΙΤΗ κατάσταση, και συμπεριφέρεται διαφορετικά
  // και από την υγιή και από την ασύμβατη: επιτρέπεται —μπορεί να είναι το
  // μόνο αντίγραφο— αλλά ποτέ χωρίς ο χρήστης να τη ζητήσει ρητά δύο φορές.
  group('βάση αντιγράφου με φθορά', () {
    const corrupted = DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      callCount: 496,
      userCount: 102,
      latestCallDate: '2026-09-04',
      contentIntegrity: DatabaseIntegrityStatus.corrupt,
      integrityDetail: 'Tree 18 page 2141: btreeInitPage() returns error 11',
    );

    const corruptedTitle = 'Βάση δεδομένων — προσοχή';

    testWidgets('το κουτάκι ανοίγει, αλλά έρχεται ΞΕΤΣΕΚΑΡΙΣΤΟ', (
      tester,
    ) async {
      await _open(tester, backupProfile: corrupted);
      expect(
        _isChecked(tester, corruptedTitle),
        isFalse,
        reason: 'Η επικίνδυνη ενέργεια δεν προεπιλέγεται',
      );
      expect(
        _isEnabled(tester, corruptedTitle),
        isTrue,
        reason: 'Ο χρήστης πρέπει να ΜΠΟΡΕΙ να τη ζητήσει, όχι να την πάθει',
      );
    });

    testWidgets('η φθορά ονομάζεται, και τα πλήθη δηλώνονται αναξιόπιστα', (
      tester,
    ) async {
      await _open(tester, backupProfile: corrupted);
      expect(find.textContaining('δεν διαβάζεται'), findsWidgets);
      expect(find.textContaining('δεν είναι αξιόπιστος'), findsOneWidget);
    });

    testWidgets('ξεκλειδώνει ΚΑΙ εκεί που η βάση θα ήταν υποχρεωτική', (
      tester,
    ) async {
      // Χωρίς αυτό, ένα μη-πλήρες αντίγραφο θα επέβαλλε τη φθαρμένη βάση:
      // κλειδωμένο ανοιχτό κουτάκι σημαίνει «θα γίνει ό,τι κι αν πεις».
      await _open(
        tester,
        backupProfile: corrupted,
        allowSkippingDatabase: false,
        presence: const BackupZipPortablePresence(hasManifest: true),
      );
      expect(_isEnabled(tester, corruptedTitle), isTrue);
      expect(_isChecked(tester, corruptedTitle), isFalse);
    });

    testWidgets('χωρίς τη βάση επιλεγμένη, καμία ερώτηση για φθορά', (
      tester,
    ) async {
      await _open(tester, backupProfile: corrupted);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Επαναφορά 4 στοιχείων'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Η βάση του αντιγράφου έχει φθορά'), findsNothing);
    });

    testWidgets(
      'με τη βάση επιλεγμένη ρωτά δεύτερη φορά, με το ωμό κείμενο του SQLite',
      (tester) async {
        await _open(tester, backupProfile: corrupted);
        await tester.tap(_checkboxOf(corruptedTitle));
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(FilledButton, 'Επαναφορά 5 στοιχείων'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Η βάση του αντιγράφου έχει φθορά'), findsOneWidget);
        expect(find.textContaining('btreeInitPage'), findsOneWidget);
      },
    );

    testWidgets('«Πίσω» στη δεύτερη ερώτηση αφήνει τον οδηγό ανοιχτό', (
      tester,
    ) async {
      await _open(tester, backupProfile: corrupted);
      await tester.tap(_checkboxOf(corruptedTitle));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Επαναφορά 5 στοιχείων'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Πίσω'));
      await tester.pumpAndSettle();

      expect(find.text('Η βάση του αντιγράφου έχει φθορά'), findsNothing);
      expect(
        find.text('Επαναφορά από αντίγραφο'),
        findsOneWidget,
        reason: 'Η απόφαση δεν πάρθηκε — ο χρήστης επιστρέφει στις επιλογές',
      );
    });

    testWidgets('«Επαναφορά παρά τη ζημιά» κλείνει τον οδηγό και προχωρά', (
      tester,
    ) async {
      await _open(tester, backupProfile: corrupted);
      await tester.tap(_checkboxOf(corruptedTitle));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Επαναφορά 5 στοιχείων'),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, 'Επαναφορά παρά τη ζημιά'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Επαναφορά από αντίγραφο'), findsNothing);
    });
  });
  group('η σύγκριση ξεχωρίζει το κενό από το «δεν διαβάζεται»', () {
    /// Φθαρμένο αντίγραφο: κλήσεις και τελευταία κλήση δεν διαβάστηκαν,
    /// ο εξοπλισμός διαβάστηκε κανονικά. Τα πλήθη είναι μετρημένα σε
    /// πραγματική φθαρμένη βάση (14/09).
    const corruptBackup = DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      equipmentCount: 400,
      userCount: 0,
      contentIntegrity: DatabaseIntegrityStatus.corrupt,
      integrityDetail: 'database disk image is malformed',
      unreadableMetrics: <DatabaseProfileMetric>{
        DatabaseProfileMetric.calls,
        DatabaseProfileMetric.latestCall,
      },
    );

    /// Υγιές αντίγραφο χωρίς καμία κλήση: τα ίδια `null`, άλλη σημασία.
    const emptyBackup = DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      callCount: 0,
      userCount: 0,
      equipmentCount: 0,
    );

    Future<void> showComparison(
      WidgetTester tester,
      DatabaseFileProfile backup,
    ) async {
      await _open(tester, backupProfile: backup);
      // Η φθαρμένη βάση δεν προεπιλέγεται — ο τίτλος της γράφει «— προσοχή»
      // και το κουτάκι ξεκινά άδειο. Ο πίνακας εμφανίζεται μόλις ο χρήστης
      // ζητήσει ρητά την επαναφορά της.
      final databaseRow = find.byType(CheckboxListTile).first;
      if (tester.widget<CheckboxListTile>(databaseRow).value != true) {
        await tester.tap(databaseRow);
        await tester.pumpAndSettle();
      }
    }

    testWidgets('ό,τι δεν διαβάστηκε το λέει με λέξεις', (tester) async {
      await showComparison(tester, corruptBackup);

      expect(find.text('Σύγκριση'), findsOneWidget);
      expect(
        find.text(unreadablePlaceholder),
        findsNWidgets(2),
        reason: 'Κλήσεις και τελευταία κλήση δεν διαβάστηκαν',
      );
      expect(
        find.text('400'),
        findsOneWidget,
        reason: 'Ο εξοπλισμός διαβάστηκε — μένει αριθμός',
      );
    });

    testWidgets('υγιές αντίγραφο χωρίς κλήσεις κρατά την παύλα', (
      tester,
    ) async {
      await showComparison(tester, emptyBackup);

      expect(
        find.text(unreadablePlaceholder),
        findsNothing,
        reason: 'Τίποτα δεν απέτυχε — απλώς δεν υπάρχουν κλήσεις',
      );
      expect(
        find.text(dashPlaceholder),
        findsWidgets,
        reason: 'Η τελευταία κλήση λείπει επειδή δεν έγινε ποτέ καμία',
      );
    });
  });
}
