// Startup hook: αυτόματο μήνυμα διαθέσιμης ενημέρωσης (μία φορά / συνεδρία).
//
//   flutter test test/core/about/update_startup_prompt_test.dart

import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:call_logger/core/updates/update_startup_prompt.dart';
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

  final available = UpdateCheckResult(
    updateAvailable: true,
    latestVersion: '0.24.0',
    manifest: manifest,
  );

  setUp(() {
    resetUpdateStartupPromptSessionForTests();
  });

  Future<ProviderContainer> pumpListener(
    WidgetTester tester, {
    required UpdateCheckResult result,
    required Future<bool> Function() getShowUpdateOnStartup,
  }) async {
    final container = ProviderContainer(
      overrides: [
        updateCheckProvider.overrideWith((ref) async => result),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: UpdateStartupPromptListener(
              getShowUpdateOnStartup: getShowUpdateOnStartup,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'με διαθέσιμη ενημέρωση και ρύθμιση true εμφανίζεται ο διάλογος μία φορά',
    (tester) async {
      await pumpListener(
        tester,
        result: available,
        getShowUpdateOnStartup: () async => true,
      );

      expect(find.text('Διαθέσιμη νέα έκδοση'), findsOneWidget);
      expect(find.textContaining('0.24.0'), findsWidgets);
    },
  );

  testWidgets(
    'με ρύθμιση false δεν εμφανίζεται ο διάλογος',
    (tester) async {
      await pumpListener(
        tester,
        result: available,
        getShowUpdateOnStartup: () async => false,
      );

      expect(find.text('Διαθέσιμη νέα έκδοση'), findsNothing);
    },
  );

  testWidgets(
    'δεύτερη ενεργοποίηση στην ίδια συνεδρία δεν ξαναεμφανίζει τον διάλογο',
    (tester) async {
      final container = await pumpListener(
        tester,
        result: available,
        getShowUpdateOnStartup: () async => true,
      );

      expect(find.text('Διαθέσιμη νέα έκδοση'), findsOneWidget);
      await tester.tap(find.text('Αργότερα'));
      await tester.pumpAndSettle();
      expect(find.text('Διαθέσιμη νέα έκδοση'), findsNothing);

      container.invalidate(updateCheckProvider);
      await tester.pumpAndSettle();

      expect(find.text('Διαθέσιμη νέα έκδοση'), findsNothing);
    },
  );
}
