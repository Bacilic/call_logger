// Ο διάλογος αναβάθμισης «Νέο επίπεδο!»: το παράσημο επιπέδου, και η επεξήγηση
// «αναπροσαρμογή αρίθμησης» που εμφανίζεται ΜΟΝΟ στη σπάνια ανωμαλία (νεότερο
// build, «μικρότερη» ετικέτα).
//
//   flutter test test/core/updates/update_available_dialog_note_test.dart

import 'package:call_logger/core/about/models/changelog_entry.dart';
import 'package:call_logger/core/about/providers/changelog_provider.dart';
import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_dialogs.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  const channelManifest = UpdateManifest(
    version: '0.23.2',
    build: 33,
    released: '2026-08-03',
    zipFile: 'call_logger_0.23.2.zip',
    sha256: 'abc',
  );

  Future<void> pumpAndOpenDialog(
    WidgetTester tester,
    UpdateCheckResult result,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          changelogProvider.overrideWith(
            (ref) async => const [
              ChangelogEntry(
                version: '0.24.4',
                date: '2026-07-19',
                added: [],
                improvements: [],
                changed: [],
                fixed: [],
              ),
            ],
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showUpdateAvailableDialog(context, result),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'realignment case shows the explanation with builds and dates',
    (tester) async {
      const result = UpdateCheckResult(
        updateAvailable: true,
        latestVersion: '0.23.2',
        manifest: channelManifest,
        currentVersion: '0.24.4',
        currentBuild: 25,
      );

      await pumpAndOpenDialog(tester, result);

      expect(find.text('Νέο επίπεδο!'), findsOneWidget);
      final content = tester
          .widget<Text>(find.textContaining('αναπροσαρμόστηκε'))
          .data!;
      expect(content, contains('κτισίματος 33 (Δευ 03 - Αυγ - 2026)'));
      expect(content, contains('εγκατεστημένο 25 (Κυρ 19 - Ιουλ - 2026)'));
      expect(content, contains('Δεν πρόκειται για υποβάθμιση'));
    },
  );

  testWidgets(
    'rebuilt same version explains it as changes without history entry',
    (tester) async {
      const result = UpdateCheckResult(
        updateAvailable: true,
        latestVersion: '0.24.4',
        manifest: UpdateManifest(
          version: '0.24.4',
          build: 26,
          released: '2026-08-04',
          zipFile: 'call_logger_0.24.4.zip',
          sha256: 'abc',
        ),
        currentVersion: '0.24.4',
        currentBuild: 25,
      );

      await pumpAndOpenDialog(tester, result);

      final content = tester
          .widget<Text>(find.textContaining('Σημείωση:'))
          .data!;
      expect(content, contains('είναι ο ίδιος με τον εγκατεστημένο'));
      expect(content, contains('δεν άλλαξαν το ιστορικό εκδόσεων'));
      expect(content, contains('κτισίματος 26 (Τρι 04 - Αυγ - 2026)'));
      // ΟΧΙ το μήνυμα της αναπροσαρμογής αρίθμησης — άλλη αιτία.
      expect(content, isNot(contains('αναπροσαρμόστηκε')));
    },
  );

  testWidgets(
    'normal upgrade shows NO realignment explanation',
    (tester) async {
      const result = UpdateCheckResult(
        updateAvailable: true,
        latestVersion: '0.24.0',
        manifest: UpdateManifest(
          version: '0.24.0',
          build: 34,
          released: '2026-08-04',
          zipFile: 'call_logger_0.24.0.zip',
          sha256: 'abc',
        ),
        currentVersion: '0.23.2',
        currentBuild: 33,
      );

      await pumpAndOpenDialog(tester, result);

      expect(find.text('Νέο επίπεδο!'), findsOneWidget);
      expect(find.textContaining('αναπροσαρμόστηκε'), findsNothing);
      expect(find.textContaining('υποβάθμιση'), findsNothing);
      expect(
        find.text(
          'Θέλετε να αναβαθμίσετε στην έκδοση 0.24.0 (Τρι 04 - Αυγ - 2026);',
        ),
        findsOneWidget,
      );
    },
  );

  // Το παράσημο γιορτάζει την αναβάθμιση: ο μεγάλος αριθμός είναι το επίπεδο,
  // η πλήρης ετικέτα έκδοσης μπαίνει από κάτω.
  testWidgets('το παράσημο δείχνει επίπεδο και πλήρη έκδοση', (tester) async {
    const result = UpdateCheckResult(
      updateAvailable: true,
      latestVersion: '0.34.0',
      manifest: UpdateManifest(
        version: '0.34.0',
        build: 52,
        released: '2026-08-08',
        zipFile: 'call_logger_0.34.0.zip',
        sha256: 'abc',
      ),
      currentVersion: '0.33.0',
      currentBuild: 51,
    );

    await pumpAndOpenDialog(tester, result);

    expect(
      tester
          .widget<Text>(find.byKey(const Key('update_level_badge_level')))
          .data,
      '34',
      reason: greekExpectMsg(
        'Το επίπεδο είναι ο αριθμός που ανεβαίνει σε κάθε δημοσίευση (minor)',
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('update_level_badge_version')))
          .data,
      'v0.34.0',
    );
  });

  // Σπάνια περίπτωση: ο αριθμός έκδοσης δεν ανεβαίνει. Το παράσημο μένει ίδιο —
  // την εξήγηση με τους αριθμούς κτισίματος τη δίνει το κείμενο δίπλα του.
  testWidgets('σε ίδιο αριθμό έκδοσης το παράσημο δείχνει το ίδιο επίπεδο', (
    tester,
  ) async {
    const result = UpdateCheckResult(
      updateAvailable: true,
      latestVersion: '0.24.4',
      manifest: UpdateManifest(
        version: '0.24.4',
        build: 26,
        released: '2026-08-04',
        zipFile: 'call_logger_0.24.4.zip',
        sha256: 'abc',
      ),
      currentVersion: '0.24.4',
      currentBuild: 25,
    );

    await pumpAndOpenDialog(tester, result);

    expect(
      tester
          .widget<Text>(find.byKey(const Key('update_level_badge_level')))
          .data,
      '24',
    );
    expect(find.textContaining('κτισίματος 26'), findsOneWidget);
  });
}
