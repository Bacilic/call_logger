import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/about/widgets/version_chip.dart';
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

  testWidgets('shows red badge when update is available', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '0.23.1'),
          updateCheckProvider.overrideWith(
            (ref) async => UpdateCheckResult(
              updateAvailable: true,
              latestVersion: '0.24.0',
              manifest: manifest,
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: VersionChip(extended: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('version_update_badge')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('hides red badge when no update is available', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '0.23.1'),
          updateCheckProvider.overrideWith(
            (ref) async => const UpdateCheckResult.none(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: VersionChip(extended: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('version_update_badge')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
