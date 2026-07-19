// ChangelogDialog — κουμπί «Ενημέρωση» όταν υπάρχει διαθέσιμη έκδοση.
//
//   flutter test test/core/about/changelog_dialog_update_button_test.dart

import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/about/providers/changelog_provider.dart';
import 'package:call_logger/core/about/widgets/changelog_dialog.dart';
import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manifest = UpdateManifest(
    version: '0.24.0',
    build: 32,
    released: '2026-07-19',
    zipFile: 'call_logger_0.24.0.zip',
    sha256: 'abc',
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required UpdateCheckResult updateResult,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '0.23.1'),
          changelogProvider.overrideWith((ref) async => const []),
          updateCheckProvider.overrideWith((ref) async => updateResult),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ChangelogDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'κουμπί Ενημέρωση ορατό όταν υπάρχει διαθέσιμη ενημέρωση με manifest',
    (tester) async {
      await pumpDialog(
        tester,
        updateResult: UpdateCheckResult(
          updateAvailable: true,
          latestVersion: '0.24.0',
          manifest: manifest,
        ),
      );

      expect(find.byKey(const Key('changelog_update_button')), findsOneWidget);
      expect(find.text('Ενημέρωση'), findsOneWidget);
      expect(find.text('Κλείσιμο'), findsOneWidget);
    },
  );

  testWidgets(
    'κουμπί Ενημέρωση κρυφό όταν δεν υπάρχει διαθέσιμη ενημέρωση',
    (tester) async {
      await pumpDialog(
        tester,
        updateResult: const UpdateCheckResult.none(),
      );

      expect(find.byKey(const Key('changelog_update_button')), findsNothing);
      expect(find.text('Ενημέρωση'), findsNothing);
      expect(find.text('Κλείσιμο'), findsOneWidget);
    },
  );
}
