// Η επεξήγηση «αναπροσαρμογή αρίθμησης» στον διάλογο «Διαθέσιμη νέα έκδοση»
// εμφανίζεται ΜΟΝΟ στη σπάνια ανωμαλία (νεότερο build, «μικρότερη» ετικέτα).
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

      expect(find.text('Διαθέσιμη νέα έκδοση'), findsOneWidget);
      final content = tester
          .widget<Text>(find.textContaining('αναπροσαρμόστηκε'))
          .data!;
      expect(content, contains('κτισίματος 33 (03-08-2026)'));
      expect(content, contains('εγκατεστημένο 25 (19-07-2026)'));
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
      expect(content, contains('κτισίματος 26 (04-08-2026)'));
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

      expect(find.text('Διαθέσιμη νέα έκδοση'), findsOneWidget);
      expect(find.textContaining('αναπροσαρμόστηκε'), findsNothing);
      expect(find.textContaining('υποβάθμιση'), findsNothing);
      // Η ημερομηνία εμφανίζεται σε μορφή ηη-ΜΜ-εεεε.
      expect(find.textContaining('(04-08-2026)'), findsOneWidget);
    },
  );
}
