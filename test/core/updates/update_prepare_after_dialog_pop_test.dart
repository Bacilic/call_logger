// Αναπαραγωγή / διόρθωση: StateError από WidgetRef μετά το κλείσιμο διαλόγου
// κατά την προετοιμασία ενημέρωσης (Ιστορικό Αλλαγών → Ενημέρωση).
//
//   flutter test test/core/updates/update_prepare_after_dialog_pop_test.dart

import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/about/providers/changelog_provider.dart';
import 'package:call_logger/core/about/widgets/changelog_dialog.dart';
import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_installer_service.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImmediateSuccessInstaller extends UpdateInstallerService {
  _ImmediateSuccessInstaller()
      : super(
          installDirectory: '.',
          resolveUpdateFolder: () async => null,
          launchDetached: (exe, args, {workingDirectory}) async {},
          terminateApp: () async {},
          isDevelopmentBuild: () => false,
        );

  @override
  Future<UpdateInstallResult> prepareUpdate(
    UpdateManifest manifest, {
    void Function(String message)? onProgressOverride,
  }) async {
    onProgressOverride?.call('Δοκιμή…');
    return const UpdateInstallResult(
      status: UpdateInstallStatus.success,
      message: 'Η ενημέρωση είναι έτοιμη.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manifest = UpdateManifest(
    version: '0.25.0',
    build: 40,
    released: '2026-07-22',
    zipFile: 'call_logger_0.25.0.zip',
    sha256: 'abc',
  );

  testWidgets(
    'WidgetRef.invalidate μετά το pop Consumer διαλόγου ρίχνει StateError '
    '(παλιό μοτίβο)',
    (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('open'),
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (dialogContext) => Consumer(
                        builder: (c, ref, _) {
                          return AlertDialog(
                            actions: [
                              TextButton(
                                key: const Key('go'),
                                onPressed: () {
                                  capturedRef = ref;
                                  Navigator.of(c, rootNavigator: true).pop();
                                },
                                child: const Text('go'),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();

      expect(
        () => capturedRef.invalidate(pendingUpdateProvider),
        throwsA(isA<StateError>()),
      );
    },
  );

  testWidgets(
    'ProviderContainer.invalidate μετά το pop Consumer διαλόγου είναι ασφαλές',
    (tester) async {
      late ProviderContainer containerAfterPop;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('open'),
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (dialogContext) => Consumer(
                        builder: (c, ref, _) {
                          return AlertDialog(
                            actions: [
                              TextButton(
                                key: const Key('go'),
                                onPressed: () {
                                  final nav =
                                      Navigator.of(c, rootNavigator: true);
                                  nav.pop();
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    final ctx = nav.context;
                                    containerAfterPop =
                                        ProviderScope.containerOf(ctx);
                                    containerAfterPop
                                        .invalidate(pendingUpdateProvider);
                                  });
                                },
                                child: const Text('go'),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();

      expect(containerAfterPop, isNotNull);
    },
  );

  testWidgets(
    'ChangelogDialog → Ενημέρωση μετά το pop δεν ρίχνει StateError '
    'και εμφανίζει διάλογο ετοιμότητας',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionProvider.overrideWith((ref) async => '0.24.5'),
            changelogProvider.overrideWith((ref) async => const []),
            updateCheckProvider.overrideWith(
              (ref) async => UpdateCheckResult(
                updateAvailable: true,
                latestVersion: '0.25.0',
                manifest: manifest,
              ),
            ),
            updateInstallerServiceProvider.overrideWithValue(
              _ImmediateSuccessInstaller(),
            ),
            pendingUpdateProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('open_changelog'),
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const ChangelogDialog(),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_changelog')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('changelog_update_button')));
      await tester.pump(); // post-frame + progress dialog
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Η ενημέρωση είναι έτοιμη'), findsOneWidget);
      expect(find.text('Αργότερα'), findsOneWidget);
    },
  );
}
