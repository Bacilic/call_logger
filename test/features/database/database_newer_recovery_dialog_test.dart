// Διάλογος «Η βάση είναι από νεότερη έκδοση» — συμπεριφορά κουμπιών.
//
// Η απόφαση του χρήστη: όταν η υποβάθμιση ΔΕΝ είναι γεφυρώσιμη, τα δύο
// κουμπιά εμφανίζονται ΑΠΕΝΕΡΓΟΠΟΙΗΜΕΝΑ με τον λόγο δίπλα — ο χρήστης
// μαθαίνει ότι η επιλογή υπάρχει και γιατί δεν ισχύει εδώ.
//
//   flutter test test/features/database/database_newer_recovery_dialog_test.dart

import 'package:call_logger/core/database/schema_downgrade_compatibility.dart';
import 'package:call_logger/core/updates/app_upgrade_offer.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:call_logger/core/services/app_instance_registry.dart';
import 'package:call_logger/features/database/widgets/database_newer_recovery_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<DatabaseNewerVersionChoice?> pumpDialog(
    WidgetTester tester, {
    required SchemaDowngradeAssessment? assessment,
    AppInstanceRecord? newerInstance,
    AppUpgradeOffer? upgradeOffer,
  }) async {
    DatabaseNewerVersionChoice? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDatabaseNewerVersionChoiceDialog(
                    context: context,
                    dbPath: r'C:\Data\Hospital.db',
                    fileVersion: 45,
                    appVersion: 40,
                    assessment: assessment,
                    newerInstance: newerInstance,
                    upgradeOffer: upgradeOffer,
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
    return captured;
  }

  testWidgets('μη γεφυρώσιμη → κουμπιά ανενεργά και ορατός λόγος', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      assessment: const SchemaDowngradeAssessment(
        fileVersion: 45,
        appVersion: 40,
        blockers: [
          'λείπει η στήλη «issue_refined» του πίνακα «calls» '
              'που χρειάζεται αυτή η έκδοση',
        ],
      ),
    );

    final copyButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('newer_db_downgrade_copy_button')),
    );
    final originalButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('newer_db_downgrade_original_button')),
    );
    expect(copyButton.onPressed, isNull);
    expect(originalButton.onPressed, isNull);

    final reason = tester.widget<Text>(
      find.byKey(const Key('newer_db_downgrade_reason')),
    );
    expect(reason.data, contains('Δεν είναι δυνατή'));
    expect(reason.data, contains('issue_refined'));
  });

  testWidgets('χωρίς αξιολόγηση → κουμπιά ανενεργά με λόγο αδυναμίας ελέγχου', (
    tester,
  ) async {
    await pumpDialog(tester, assessment: null);

    final copyButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('newer_db_downgrade_copy_button')),
    );
    expect(copyButton.onPressed, isNull);
    final reason = tester.widget<Text>(
      find.byKey(const Key('newer_db_downgrade_reason')),
    );
    expect(reason.data, contains('έλεγχος συμβατότητας'));
  });

  testWidgets('γεφυρώσιμη → το πάτημα «αντίγραφο» επιστρέφει την επιλογή', (
    tester,
  ) async {
    DatabaseNewerVersionChoice? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDatabaseNewerVersionChoiceDialog(
                    context: context,
                    dbPath: r'C:\Data\Hospital.db',
                    fileVersion: 42,
                    appVersion: 40,
                    assessment: const SchemaDowngradeAssessment(
                      fileVersion: 42,
                      appVersion: 40,
                      blockers: [],
                    ),
                    newerInstance: null,
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

    // Χωρίς λόγο αποκλεισμού δεν υπάρχει κείμενο αιτιολόγησης.
    expect(find.byKey(const Key('newer_db_downgrade_reason')), findsNothing);

    // Στη μικρή οθόνη των τεστ το κουμπί χρειάζεται κύλιση για να φανεί.
    await tester.ensureVisible(
      find.byKey(const Key('newer_db_downgrade_copy_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('newer_db_downgrade_copy_button')));
    await tester.pumpAndSettle();
    expect(captured, DatabaseNewerVersionChoice.downgradeCopy);
  });

  testWidgets(
    'με γνωστή νεότερη εγκατάσταση → φαίνεται η διαδρομή και το κουμπί '
    'εκκίνησης επιστρέφει την επιλογή',
    (tester) async {
      DatabaseNewerVersionChoice? captured;
      final instance = AppInstanceRecord(
        executablePath: r'F:\Apps\CallLoggerNew\call_logger.exe',
        version: '0.38.0',
        lastSeen: DateTime(2026, 8, 10),
        schemaVersion: 45,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showDatabaseNewerVersionChoiceDialog(
                      context: context,
                      dbPath: r'C:\Data\Hospital.db',
                      fileVersion: 45,
                      appVersion: 40,
                      assessment: null,
                      newerInstance: instance,
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

      expect(
        find.text(r'F:\Apps\CallLoggerNew\call_logger.exe'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('newer_db_launch_newer_button')));
      await tester.pumpAndSettle();
      expect(captured, DatabaseNewerVersionChoice.launchNewer);
    },
  );

  AppUpgradeOffer offerOf(AppUpgradeConfidence confidence) => AppUpgradeOffer(
    manifest: const UpdateManifest(
      version: '0.40.0',
      build: 400,
      released: '2026-08-25',
      zipFile: 'call_logger_0.40.0(400).zip',
      sha256: 'abc123',
      schemaVersion: 45,
    ),
    confidence: confidence,
  );

  testWidgets('με διαθέσιμο πακέτο → κουμπί αναβάθμισης με την έκδοση', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      assessment: null,
      upgradeOffer: offerOf(AppUpgradeConfidence.resolvesForSure),
    );

    expect(
      find.byKey(const Key('newer_db_upgrade_app_button')),
      findsOneWidget,
    );
    expect(find.text('Αναβάθμιση στην έκδοση 0.40.0'), findsOneWidget);
  });

  testWidgets('το πάτημα της αναβάθμισης επιστρέφει την επιλογή', (
    tester,
  ) async {
    DatabaseNewerVersionChoice? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDatabaseNewerVersionChoiceDialog(
                    context: context,
                    dbPath: r'C:\Data\Hospital.db',
                    fileVersion: 45,
                    appVersion: 40,
                    assessment: null,
                    newerInstance: null,
                    upgradeOffer: offerOf(AppUpgradeConfidence.resolvesForSure),
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

    await tester.ensureVisible(
      find.byKey(const Key('newer_db_upgrade_app_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('newer_db_upgrade_app_button')));
    await tester.pumpAndSettle();

    expect(captured, DatabaseNewerVersionChoice.upgradeApp);
  });

  testWidgets('χωρίς δηλωμένη έκδοση βάσης η υπόσχεση δεν εγγυάται', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      assessment: null,
      upgradeOffer: offerOf(AppUpgradeConfidence.likelyResolves),
    );

    expect(
      find.byKey(const Key('newer_db_upgrade_app_button')),
      findsOneWidget,
    );
    expect(find.textContaining('χωρίς εγγύηση'), findsOneWidget);
  });

  testWidgets('χωρίς διαθέσιμο πακέτο δεν υπάρχει κουμπί αναβάθμισης', (
    tester,
  ) async {
    await pumpDialog(tester, assessment: null);

    expect(find.byKey(const Key('newer_db_upgrade_app_button')), findsNothing);
    expect(
      find.textContaining('Δεν βρέθηκε νεότερο πακέτο εγκατάστασης'),
      findsOneWidget,
    );
  });
}
