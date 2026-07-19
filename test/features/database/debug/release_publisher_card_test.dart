import 'dart:async';
import 'dart:io';

import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/updates/network_folder_classifier.dart';
import 'package:call_logger/features/database/debug/release_publisher_card.dart';
import 'package:call_logger/features/database/debug/release_publisher_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory projectRoot;

  NetworkFolderClassifier fixedKind(NetworkFolderKind kind) {
    return _FixedKindClassifier(kind);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('release_card_');
    projectRoot = Directory(p.join(tempDir.path, 'project'));
    await Directory(p.join(projectRoot.path, 'assets')).create(recursive: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    String? initialFolder,
    String currentVersion = '0.23.1',
    NetworkFolderClassifier? networkFolderClassifier,
    ReleasePublisherService Function({
      required String updateFolderPath,
      void Function(String message)? onProgress,
    })? serviceFactory,
  }) async {
    if (initialFolder != null) {
      SharedPreferences.setMockInitialValues({
        'update_folder_path': initialFolder,
      });
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => currentVersion),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReleasePublisherCard(
                networkFolderClassifier:
                    networkFolderClassifier ??
                        fixedKind(NetworkFolderKind.unknown),
                networkClassifyDebounce: Duration.zero,
                serviceFactory: serviceFactory,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilledButton findPublishButton(WidgetTester tester) {
    return tester.widget<FilledButton>(
      find.byKey(const Key('release_publish_button')),
    );
  }

  testWidgets('empty folder disables publish with tooltip', (tester) async {
    await pumpCard(tester);

    expect(findPublishButton(tester).onPressed, isNull);
    expect(
      find.byTooltip('Ορίστε έγκυρο εγγράψιμο φάκελο ενημερώσεων'),
      findsNWidgets(2),
    );
  });

  testWidgets('invalid folder disables publish with tooltip', (tester) async {
    await pumpCard(tester);

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      r'C:\this\path\almost\certainly\does\not\exist_xyz_12345',
    );
    await tester.pumpAndSettle();

    expect(findPublishButton(tester).onPressed, isNull);
    expect(
      find.byTooltip('Ορίστε έγκυρο εγγράψιμο φάκελο ενημερώσεων'),
      findsNWidgets(2),
    );
  });

  testWidgets('valid writable folder enables publish', (tester) async {
    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      networkFolderClassifier: fixedKind(NetworkFolderKind.unknown),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    expect(findPublishButton(tester).onPressed, isNotNull);
    expect(
      find.byTooltip('Ορίστε έγκυρο εγγράψιμο φάκελο ενημερώσεων'),
      findsNothing,
    );
  });

  testWidgets('bump chips show dynamic next-version tooltips', (tester) async {
    await pumpCard(tester, currentVersion: '0.26.7');

    expect(
      find.byTooltip(
        'Μικρή αναβάθμιση για διορθώσεις σφαλμάτων — π.χ. 0.26.7 → 0.26.8',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        'Μεγαλύτερη αναβάθμιση για νέες δυνατότητες — π.χ. 0.26.7 → 0.27.0',
      ),
      findsOneWidget,
    );
  });

  testWidgets('localOnly warning visible only for localOnly', (tester) async {
    await pumpCard(
      tester,
      networkFolderClassifier: fixedKind(NetworkFolderKind.localOnly),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('release_update_folder_local_only_warning')),
      findsOneWidget,
    );
    expect(find.textContaining('τοπική διαδρομή'), findsOneWidget);
  });

  testWidgets('no warning for networkUnc', (tester) async {
    await pumpCard(
      tester,
      networkFolderClassifier: fixedKind(NetworkFolderKind.networkUnc),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('release_update_folder_local_only_warning')),
      findsNothing,
    );
  });

  testWidgets('no warning for localShared', (tester) async {
    await pumpCard(
      tester,
      networkFolderClassifier: fixedKind(NetworkFolderKind.localShared),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('release_update_folder_local_only_warning')),
      findsNothing,
    );
  });

  testWidgets('no warning for unknown', (tester) async {
    await pumpCard(
      tester,
      networkFolderClassifier: fixedKind(NetworkFolderKind.unknown),
    );

    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('release_update_folder_local_only_warning')),
      findsNothing,
    );
  });

  testWidgets(
    'publish with entries shows confirm dialog with version transition',
    (tester) async {
      var publishCalls = 0;

      await pumpCard(
        tester,
        initialFolder: tempDir.path,
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _TrackingPublisherService(
            projectRoot: projectRoot.path,
            updateFolderPath: updateFolderPath,
            onPublish: () => publishCalls++,
            preview: const ReleasePublishPreview(
              currentVersion: '0.23.1',
              currentBuild: 31,
              nextVersion: '0.23.2',
              nextBuild: 32,
              unreleasedEntryCount: 1,
              hasUnreleasedEntries: true,
            ),
          );
        },
      );
      await tester.enterText(
        find.byKey(const Key('release_update_folder_field')),
        tempDir.path,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('release_publish_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('release_confirm_dialog')), findsOneWidget);
      expect(find.textContaining('0.23.1+31 → 0.23.2+32'), findsOneWidget);
      expect(publishCalls, 0);

      await tester.tap(find.byKey(const Key('release_confirm_cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(publishCalls, 0);
    },
  );

  testWidgets('empty Unreleased shows warning; cancel does not publish',
      (tester) async {
    var publishCalls = 0;

    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () => publishCalls++,
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 0,
            hasUnreleasedEntries: false,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_publish_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const Key('release_empty_unreleased_dialog')),
      findsOneWidget,
    );
    expect(find.text('Δημοσίευση όπως είναι'), findsOneWidget);

    await tester.tap(find.byKey(const Key('release_empty_cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(publishCalls, 0);
  });

  testWidgets('empty Unreleased dialog includes installer-only option',
      (tester) async {
    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () {},
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 0,
            hasUnreleasedEntries: false,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_publish_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Μόνο εγκαταστάτης'), findsOneWidget);
    expect(
      find.byKey(const Key('release_empty_installer_only')),
      findsOneWidget,
    );
  });

  testWidgets('installer button calls writeInstallerOnly not publish',
      (tester) async {
    var publishCalls = 0;
    var installerCalls = 0;

    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () => publishCalls++,
          onWriteInstaller: () => installerCalls++,
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 1,
            hasUnreleasedEntries: true,
          ),
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_installer_only_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(installerCalls, 1);
    expect(publishCalls, 0);
  });

  testWidgets('while slow installer runs both buttons disabled and timer shows',
      (tester) async {
    final gate = Completer<ReleasePublishResult>();

    await pumpCard(
      tester,
      initialFolder: tempDir.path,
      serviceFactory: ({required updateFolderPath, onProgress}) {
        return _TrackingPublisherService(
          projectRoot: projectRoot.path,
          updateFolderPath: updateFolderPath,
          onPublish: () {},
          preview: const ReleasePublishPreview(
            currentVersion: '0.23.1',
            currentBuild: 31,
            nextVersion: '0.23.2',
            nextBuild: 32,
            unreleasedEntryCount: 1,
            hasUnreleasedEntries: true,
          ),
          writeInstallerResult: () => gate.future,
        );
      },
    );
    await tester.enterText(
      find.byKey(const Key('release_update_folder_field')),
      tempDir.path,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('release_installer_only_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(findPublishButton(tester).onPressed, isNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('release_installer_only_button')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('release_elapsed_timer')), findsOneWidget);
    expect(find.textContaining('Χρόνος:'), findsOneWidget);

    gate.complete(
      const ReleasePublishResult(status: ReleasePublishStatus.success),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });
}

class _FixedKindClassifier extends NetworkFolderClassifier {
  _FixedKindClassifier(this.kind)
      : super(
          driveTypeResolver: (_) async => false,
          localSharesProvider: () async => const <String>[],
          isWindows: () => true,
        );

  final NetworkFolderKind kind;

  @override
  Future<NetworkFolderKind> classify(String path) async => kind;
}

class _TrackingPublisherService extends ReleasePublisherService {
  _TrackingPublisherService({
    required super.projectRoot,
    required super.updateFolderPath,
    required this.onPublish,
    required this.preview,
    this.onWriteInstaller,
    this.writeInstallerResult,
  }) : super(
          buildReleaseDirectory: p.join(projectRoot, 'build'),
          processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
          clock: () => DateTime(2026, 7, 19),
        );

  final void Function() onPublish;
  final void Function()? onWriteInstaller;
  final ReleasePublishPreview preview;
  final Future<ReleasePublishResult> Function()? writeInstallerResult;

  @override
  Future<ReleasePublishPreview> preparePreview(VersionBumpKind kind) async =>
      preview;

  @override
  Future<ReleasePublishResult> publish({
    required VersionBumpKind bumpKind,
    bool proceedDespiteEmptyUnreleased = false,
  }) async {
    onPublish();
    return const ReleasePublishResult(status: ReleasePublishStatus.success);
  }

  @override
  Future<ReleasePublishResult> writeInstallerOnly() async {
    onWriteInstaller?.call();
    if (writeInstallerResult != null) {
      return writeInstallerResult!();
    }
    return const ReleasePublishResult(status: ReleasePublishStatus.success);
  }
}
