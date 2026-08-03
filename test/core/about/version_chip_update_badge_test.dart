import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/about/widgets/version_chip.dart';
import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:call_logger/features/database/debug/publish_reminder.dart';
import 'package:call_logger/features/database/debug/publish_reminder_provider.dart';
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

  // Υπενθύμιση δημοσίευσης: το κίτρινο σήμα στο κουμπί αποσφαλμάτωσης.
  Future<void> pumpWithReminder(
    WidgetTester tester,
    PublishReminderStatus reminder,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '0.21.3'),
          updateCheckProvider.overrideWith(
            (ref) async => const UpdateCheckResult.none(),
          ),
          publishReminderProvider.overrideWith((ref) async => reminder),
        ],
        child: const MaterialApp(
          home: Scaffold(body: VersionChip(extended: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('το σήμα δημοσίευσης δείχνει το πλήθος των αδημοσίευτων αλλαγών', (
    tester,
  ) async {
    await pumpWithReminder(
      tester,
      evaluatePublishReminder(
        unreleasedEntryCount: 173,
        now: DateTime(2026, 8, 3),
        lastReleaseDate: DateTime(2026, 7, 23),
        lastReleaseVersion: '0.21.3',
      ),
    );

    expect(find.byKey(const Key('publish_reminder_badge')), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('χωρίς αδημοσίευτες αλλαγές δεν υπάρχει σήμα δημοσίευσης', (
    tester,
  ) async {
    await pumpWithReminder(
      tester,
      evaluatePublishReminder(
        unreleasedEntryCount: 0,
        now: DateTime(2026, 8, 3),
        lastReleaseDate: DateTime(2026, 5, 1),
        lastReleaseVersion: '0.21.3',
      ),
    );

    expect(
      find.byKey(const Key('publish_reminder_badge')),
      findsNothing,
      reason:
          'Ένα σήμα που ανάβει χωρίς να εκκρεμεί τίποτα παύει να σημαίνει κάτι',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
