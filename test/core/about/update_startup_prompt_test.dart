// Startup hook: αυτόματο μήνυμα διαθέσιμης ενημέρωσης (μία φορά / συνεδρία).
//
//   flutter test test/core/about/update_startup_prompt_test.dart

import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_installer_service.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:call_logger/core/updates/update_startup_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Προετοιμάζει αμέσως με επιτυχία και μετρά τις επανεκκινήσεις.
class _RecordingInstaller extends UpdateInstallerService {
  _RecordingInstaller()
    : super(
        installDirectory: '.',
        resolveUpdateFolder: () async => null,
        launchDetached: (exe, args, {workingDirectory}) async {},
        terminateApp: () async {},
        isDevelopmentBuild: () => false,
      );

  int restarts = 0;

  @override
  Future<UpdateInstallResult> prepareUpdate(
    UpdateManifest manifest, {
    void Function(String message)? onProgressOverride,
  }) async {
    return const UpdateInstallResult(status: UpdateInstallStatus.success);
  }

  @override
  Future<UpdateInstallResult> launchPendingUpdate() async {
    restarts++;
    return const UpdateInstallResult(status: UpdateInstallStatus.success);
  }
}

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
      overrides: [updateCheckProvider.overrideWith((ref) async => result)],
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

      expect(find.text('Νέο επίπεδο!'), findsOneWidget);
      expect(find.textContaining('0.24.0'), findsWidgets);
    },
  );

  testWidgets('με ρύθμιση false δεν εμφανίζεται ο διάλογος', (tester) async {
    await pumpListener(
      tester,
      result: available,
      getShowUpdateOnStartup: () async => false,
    );

    expect(find.text('Νέο επίπεδο!'), findsNothing);
  });

  testWidgets(
    'δεύτερη ενεργοποίηση στην ίδια συνεδρία δεν ξαναεμφανίζει τον διάλογο',
    (tester) async {
      final container = await pumpListener(
        tester,
        result: available,
        getShowUpdateOnStartup: () async => true,
      );

      expect(find.text('Νέο επίπεδο!'), findsOneWidget);
      await tester.tap(find.text('Αργότερα'));
      await tester.pumpAndSettle();
      expect(find.text('Νέο επίπεδο!'), findsNothing);

      container.invalidate(updateCheckProvider);
      await tester.pumpAndSettle();

      expect(find.text('Νέο επίπεδο!'), findsNothing);
    },
  );

  Future<ProviderContainer> pumpWithInstaller(
    WidgetTester tester, {
    required List<UpdateCheckResult> checks,
    required _RecordingInstaller installer,
  }) async {
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        updateCheckProvider.overrideWith(
          (ref) async => checks[(calls++).clamp(0, checks.length - 1)],
        ),
        updateInstallerServiceProvider.overrideWithValue(installer),
        pendingUpdateProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: UpdateStartupPromptListener(
              getShowUpdateOnStartup: () async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'στην εκκίνηση η «Ενημέρωση και επανεκκίνηση» επανεκκινεί χωρίς δεύτερη '
    'ερώτηση',
    (tester) async {
      final installer = _RecordingInstaller();
      await pumpWithInstaller(
        tester,
        checks: [available],
        installer: installer,
      );

      await tester.tap(find.text('Ενημέρωση και επανεκκίνηση'));
      await tester.pumpAndSettle();

      expect(find.text('Η ενημέρωση είναι έτοιμη'), findsNothing);
      expect(installer.restarts, 1);
    },
  );

  testWidgets(
    'μήνυμα από μεταγενέστερο έλεγχο (μέσα στη μέρα) κρατά την ερώτηση '
    'επανεκκίνησης',
    (tester) async {
      final installer = _RecordingInstaller();
      final container = await pumpWithInstaller(
        tester,
        checks: [const UpdateCheckResult(updateAvailable: false), available],
        installer: installer,
      );
      expect(find.text('Νέο επίπεδο!'), findsNothing);

      container.invalidate(updateCheckProvider);
      await tester.pumpAndSettle();

      expect(find.text('Ενημέρωση και επανεκκίνηση'), findsNothing);
      await tester.tap(find.text('Ενημέρωση'));
      await tester.pumpAndSettle();

      expect(find.text('Η ενημέρωση είναι έτοιμη'), findsOneWidget);
      expect(installer.restarts, 0);
    },
  );
}
