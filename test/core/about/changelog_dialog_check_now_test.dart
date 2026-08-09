// ChangelogDialog — «Έλεγχος τώρα» και ετικέτα κατάστασης ελέγχου.
//
// Το κουμπί ξανατρέχει τον έλεγχο νέας έκδοσης επιτόπου· η ετικέτα δίπλα του
// λέει πάντα τι ξέρουμε («Είστε ενημερωμένοι / Διαθέσιμη νέα έκδοση · έλεγχος
// HH:mm») — ένα κουμπί που «δεν κάνει τίποτα ορατό» μοιάζει χαλασμένο.
//
//   flutter test test/core/about/changelog_dialog_check_now_test.dart

import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/about/providers/changelog_provider.dart';
import 'package:call_logger/core/about/widgets/changelog_dialog.dart';
import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<int Function()> pumpDialog(
    WidgetTester tester, {
    required UpdateCheckResult updateResult,
  }) async {
    var checks = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '0.23.1'),
          changelogProvider.overrideWith((ref) async => const []),
          updateCheckProvider.overrideWith((ref) async {
            checks++;
            return updateResult;
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: ChangelogDialog())),
      ),
    );
    await tester.pumpAndSettle();
    return () => checks;
  }

  testWidgets('χωρίς νεότερη έκδοση: «Είστε ενημερωμένοι» με την ώρα ελέγχου', (
    tester,
  ) async {
    final checks = await pumpDialog(
      tester,
      updateResult: UpdateCheckResult(
        updateAvailable: false,
        latestVersion: '0.23.1',
        currentVersion: '0.23.1',
        currentBuild: 31,
        checkedAt: DateTime(2026, 8, 8, 14, 32),
      ),
    );

    expect(find.byKey(const Key('changelog_check_now_button')), findsOneWidget);
    final status = tester.widget<Text>(
      find.byKey(const Key('changelog_update_check_status')),
    );
    expect(status.data, contains('Είστε ενημερωμένοι'));
    expect(
      status.data,
      contains('14:32'),
      reason: greekExpectMsg(
        'Χωρίς την ώρα, ο χρήστης δεν ξέρει αν ο αυτόματος έλεγχος δουλεύει',
      ),
    );

    // Το πάτημα ξανατρέχει τον έλεγχο.
    expect(checks(), 1);
    await tester.tap(find.byKey(const Key('changelog_check_now_button')));
    await tester.pumpAndSettle();
    expect(
      checks(),
      2,
      reason: greekExpectMsg('Το «Έλεγχος τώρα» πρέπει να ξανατρέχει τον έλεγχο'),
    );
  });

  testWidgets('με διαθέσιμη έκδοση: η ετικέτα την ονομάζει', (tester) async {
    await pumpDialog(
      tester,
      updateResult: UpdateCheckResult(
        updateAvailable: true,
        latestVersion: '0.24.0',
        manifest: UpdateManifest(
          version: '0.24.0',
          build: 32,
          released: '2026-08-08',
          zipFile: 'call_logger_0.24.0.zip',
          sha256: 'abc',
        ),
        currentVersion: '0.23.1',
        currentBuild: 31,
        checkedAt: DateTime(2026, 8, 8, 9, 5),
      ),
    );

    final status = tester.widget<Text>(
      find.byKey(const Key('changelog_update_check_status')),
    );
    expect(status.data, contains('Διαθέσιμη νέα έκδοση 0.24.0'));
    expect(status.data, contains('09:05'));
    // Το υπάρχον κουμπί «Ενημέρωση» συνυπάρχει στην ίδια γραμμή.
    expect(find.byKey(const Key('changelog_update_button')), findsOneWidget);
  });

  testWidgets('χωρίς πραγματικό έλεγχο (dev build): καμία ετικέτα', (
    tester,
  ) async {
    await pumpDialog(tester, updateResult: const UpdateCheckResult.none());

    expect(
      find.byKey(const Key('changelog_update_check_status')),
      findsNothing,
      reason: greekExpectMsg(
        'Δεν ισχυριζόμαστε «Είστε ενημερωμένοι» όταν δεν κοιτάξαμε καν',
      ),
    );
    // Το κουμπί όμως υπάρχει — μπορεί να πυροδοτήσει τον πρώτο πραγματικό έλεγχο.
    expect(find.byKey(const Key('changelog_check_now_button')), findsOneWidget);
  });
}
