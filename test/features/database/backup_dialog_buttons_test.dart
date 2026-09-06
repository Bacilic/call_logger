// Οι ΙΔΙΟΙ οι διάλογοι δεν δείχνουν κουμπί που οδηγεί σε βέβαιη αποτυχία.
//
// Το συμβόλαιο: «Κανένας διάλογος δεν προσφέρει ενέργεια που η εφαρμογή ήδη
// ξέρει ότι θα αποτύχει.»
//
// Γιατί δεν αρκούν τα τεστ της απόφασης: το σφάλμα ήταν ακριβώς ότι η σωστή
// απόφαση υπήρχε στον έναν διάλογο και έλειπε από τον άλλον. Εδώ ελέγχεται τι
// βλέπει ο άνθρωπος, όχι τι επιστρέφει μια συνάρτηση.
//
//   flutter test test/features/database/backup_dialog_buttons_test.dart

import 'package:call_logger/features/database/utils/backup_destination_reachability.dart';
import 'package:call_logger/features/database/widgets/backup_folder_missing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Το πραγματικό σενάριο του Διευθυντή: δικτυακός φάκελος του νοσοκομείου,
/// ανοιγμένος από μηχάνημα εκτός αυτού του δικτύου.
const _hospitalShare =
    r'\\gnk.local\Departments\TPO\Utilities\Call Logger\Backups';

Future<void> _pumpFolderMissing(
  WidgetTester tester, {
  required String folderPath,
  required BackupDestinationReachability reach,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showBackupFolderMissingDialog(
                  context: context,
                  ref: ref,
                  folderPath: folderPath,
                  // Ο διάλογος δεν πρέπει να αγγίξει τις ρυθμίσεις σε αυτόν
                  // τον έλεγχο: μας ενδιαφέρει μόνο τι δείχνει.
                  dismissSetsStatusNone: false,
                  probeReach: (_) async => reach,
                ),
                child: const Text('άνοιξε'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('άνοιξε'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('Ο διάλογος «λείπει ο φάκελος»', () {
    testWidgets(
      'άφταστος δικτυακός φάκελος: ΔΕΝ προσφέρει δημιουργία',
      (tester) async {
        await _pumpFolderMissing(
          tester,
          folderPath: _hospitalShare,
          reach: BackupDestinationReachability.networkUnreachable,
        );

        expect(
          find.text('Δημιουργία εδώ και εκτέλεση'),
          findsNothing,
          reason:
              'Ο κοινόχρηστος δεν απαντά· η δημιουργία θα αποτύγχανε και θα '
              'έστελνε τον χρήστη στον επόμενο διάλογο.',
        );
        expect(find.text('Αλλαγή φακέλου'), findsOneWidget);
        expect(find.text('Αγνόηση'), findsOneWidget);
      },
    );

    testWidgets('άφταστος δικτυακός φάκελος: λέει ΓΙΑΤΙ', (tester) async {
      await _pumpFolderMissing(
        tester,
        folderPath: _hospitalShare,
        reach: BackupDestinationReachability.networkUnreachable,
      );

      expect(
        find.textContaining('δικτυακός φάκελος δεν απαντά'),
        findsOneWidget,
        reason:
            'Χωρίς την αιτία, ο χρήστης βλέπει ένα κουμπί λιγότερο και δεν '
            'ξέρει γιατί.',
      );
      expect(find.textContaining(_hospitalShare), findsOneWidget);
    });

    testWidgets(
      'προσβάσιμος προορισμός: η δημιουργία ΠΑΡΑΜΕΝΕΙ',
      (tester) async {
        await _pumpFolderMissing(
          tester,
          folderPath: r'D:\Backups\call_logger',
          reach: BackupDestinationReachability.creatable,
        );

        expect(
          find.text('Δημιουργία εδώ και εκτέλεση'),
          findsOneWidget,
          reason:
              'Τοπικός φάκελος που απλώς σβήστηκε: η δημιουργία είναι η '
              'σωστή και γρήγορη απάντηση.',
        );
      },
    );

    testWidgets(
      'αποσυνδεδεμένος δίσκος: ΔΕΝ προσφέρει δημιουργία',
      (tester) async {
        await _pumpFolderMissing(
          tester,
          folderPath: r'K:\Backups',
          reach: BackupDestinationReachability.volumeMissing,
        );

        expect(find.text('Δημιουργία εδώ και εκτέλεση'), findsNothing);
        expect(
          find.textContaining('Ο δίσκος K: δεν υπάρχει'),
          findsOneWidget,
          reason: 'Το γράμμα του δίσκου κατονομάζεται, δεν λέγεται αόριστα.',
        );
      },
    );
  });
}
