import 'dart:io';

import 'package:call_logger/features/database/debug/publish_cli.dart';
import 'package:call_logger/features/database/debug/release_publisher_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parsePublishCliArgs', () {
    test('parses patch bump, folder and allow-empty', () {
      final result = parsePublishCliArgs([
        '--bump=patch',
        r'--folder=C:\updates',
        '--allow-empty',
      ]);
      expect(result.error, isNull);
      expect(result.args, isNotNull);
      expect(result.args!.bumpKind, VersionBumpKind.patch);
      expect(result.args!.folder, r'C:\updates');
      expect(result.args!.allowEmpty, isTrue);
    });

    test('parses minor bump without allow-empty', () {
      final result = parsePublishCliArgs([
        '--bump=minor',
        '--folder=/share/updates',
      ]);
      expect(result.error, isNull);
      expect(result.args!.bumpKind, VersionBumpKind.minor);
      expect(result.args!.folder, '/share/updates');
      expect(result.args!.allowEmpty, isFalse);
    });

    test('rejects missing bump', () {
      final result = parsePublishCliArgs(['--folder=/x']);
      expect(result.args, isNull);
      expect(result.error, isNotNull);
    });

    test('rejects missing folder', () {
      final result = parsePublishCliArgs(['--bump=patch']);
      expect(result.args, isNull);
      expect(result.error, isNotNull);
    });

    test('rejects invalid bump', () {
      final result = parsePublishCliArgs([
        '--bump=major',
        '--folder=/x',
      ]);
      expect(result.args, isNull);
      expect(result.error, isNotNull);
    });
  });

  group('buildPublishCliCommand', () {
    test('replaces bump and folder placeholders in default template', () {
      final cmd = buildPublishCliCommand(
        kDefaultPublishCliCommandTemplate,
        VersionBumpKind.patch,
        r'\\server\share\updates',
      );
      expect(
        cmd,
        'dart run tool/publish.dart --bump=patch '
        r'--folder="\\server\share\updates"',
      );
    });

    test('replaces placeholders in custom template', () {
      final cmd = buildPublishCliCommand(
        'flutter pub run tool/publish.dart --bump={bump} --folder={folder}',
        VersionBumpKind.minor,
        r'D:\out',
      );
      expect(
        cmd,
        r'flutter pub run tool/publish.dart --bump=minor --folder=D:\out',
      );
    });
  });

  group('kPublishCliParametersHelp', () {
    test('documents bump, folder and allow-empty', () {
      expect(kPublishCliParametersHelp, contains('--bump'));
      expect(kPublishCliParametersHelp, contains('--folder'));
      expect(kPublishCliParametersHelp, contains('--allow-empty'));
    });
  });

  group('runPublishCli exit codes', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('publish_cli_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    const emptyPreview = ReleasePublishPreview(
      currentVersion: '0.23.1',
      currentBuild: 31,
      nextVersion: '0.23.2',
      nextBuild: 32,
      unreleasedEntryCount: 0,
      hasUnreleasedEntries: false,
    );

    const filledPreview = ReleasePublishPreview(
      currentVersion: '0.23.1',
      currentBuild: 31,
      nextVersion: '0.23.2',
      nextBuild: 32,
      unreleasedEntryCount: 2,
      hasUnreleasedEntries: true,
    );

    test('returns 0 on success when Unreleased has entries', () async {
      final lines = <String>[];
      final tracker = _CallTracker();
      final code = await runPublishCli(
        PublishCliArgs(
          bumpKind: VersionBumpKind.patch,
          folder: tempDir.path,
        ),
        writeLine: lines.add,
        isInteractive: false,
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _FakePublisherService(
            projectRoot: tempDir.path,
            updateFolderPath: updateFolderPath,
            onProgress: onProgress,
            preview: filledPreview,
            tracker: tracker,
            publishResult: const ReleasePublishResult(
              status: ReleasePublishStatus.success,
              message: 'ok',
            ),
          );
        },
      );
      expect(code, 0);
      expect(tracker.publishCalls, 1);
      expect(tracker.lastProceedDespiteEmpty, isFalse);
      expect(tracker.writeInstallerCalls, 0);
      expect(lines, isNotEmpty);
    });

    test('returns 1 on failure', () async {
      final tracker = _CallTracker();
      final code = await runPublishCli(
        PublishCliArgs(
          bumpKind: VersionBumpKind.patch,
          folder: tempDir.path,
        ),
        writeLine: (_) {},
        isInteractive: false,
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _FakePublisherService(
            projectRoot: tempDir.path,
            updateFolderPath: updateFolderPath,
            onProgress: onProgress,
            preview: filledPreview,
            tracker: tracker,
            publishResult: const ReleasePublishResult(
              status: ReleasePublishStatus.failure,
              failedStep: 'flutter build',
              message: 'blocked',
            ),
          );
        },
      );
      expect(code, 1);
      expect(tracker.publishCalls, 1);
    });

    test('empty Unreleased + cancel returns 2 without publish', () async {
      final tracker = _CallTracker();
      var promptCalls = 0;
      final code = await runPublishCli(
        PublishCliArgs(
          bumpKind: VersionBumpKind.patch,
          folder: tempDir.path,
        ),
        writeLine: (_) {},
        isInteractive: true,
        promptEmptyUnreleased: () {
          promptCalls++;
          return EmptyUnreleasedChoice.cancel;
        },
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _FakePublisherService(
            projectRoot: tempDir.path,
            updateFolderPath: updateFolderPath,
            onProgress: onProgress,
            preview: emptyPreview,
            tracker: tracker,
          );
        },
      );
      expect(code, 2);
      expect(promptCalls, 1);
      expect(tracker.publishCalls, 0);
      expect(tracker.writeInstallerCalls, 0);
    });

    test('empty Unreleased + installerOnly calls writeInstallerOnly', () async {
      final tracker = _CallTracker();
      final code = await runPublishCli(
        PublishCliArgs(
          bumpKind: VersionBumpKind.patch,
          folder: tempDir.path,
        ),
        writeLine: (_) {},
        isInteractive: true,
        promptEmptyUnreleased: () => EmptyUnreleasedChoice.installerOnly,
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _FakePublisherService(
            projectRoot: tempDir.path,
            updateFolderPath: updateFolderPath,
            onProgress: onProgress,
            preview: emptyPreview,
            tracker: tracker,
            writeInstallerResult: const ReleasePublishResult(
              status: ReleasePublishStatus.success,
              message: 'installer ok',
            ),
          );
        },
      );
      expect(code, 0);
      expect(tracker.writeInstallerCalls, 1);
      expect(tracker.publishCalls, 0);
    });

    test(
      'empty Unreleased + publishAnyway calls publish with proceed true',
      () async {
        final tracker = _CallTracker();
        final code = await runPublishCli(
          PublishCliArgs(
            bumpKind: VersionBumpKind.patch,
            folder: tempDir.path,
          ),
          writeLine: (_) {},
          isInteractive: true,
          promptEmptyUnreleased: () => EmptyUnreleasedChoice.publishAnyway,
          serviceFactory: ({required updateFolderPath, onProgress}) {
            return _FakePublisherService(
              projectRoot: tempDir.path,
              updateFolderPath: updateFolderPath,
              onProgress: onProgress,
              preview: emptyPreview,
              tracker: tracker,
              publishResult: const ReleasePublishResult(
                status: ReleasePublishStatus.success,
              ),
            );
          },
        );
        expect(code, 0);
        expect(tracker.publishCalls, 1);
        expect(tracker.lastProceedDespiteEmpty, isTrue);
        expect(tracker.writeInstallerCalls, 0);
      },
    );

    test('empty Unreleased + non-interactive returns 2', () async {
      final tracker = _CallTracker();
      var promptCalls = 0;
      final lines = <String>[];
      final code = await runPublishCli(
        PublishCliArgs(
          bumpKind: VersionBumpKind.patch,
          folder: tempDir.path,
        ),
        writeLine: lines.add,
        isInteractive: false,
        promptEmptyUnreleased: () {
          promptCalls++;
          return EmptyUnreleasedChoice.publishAnyway;
        },
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _FakePublisherService(
            projectRoot: tempDir.path,
            updateFolderPath: updateFolderPath,
            onProgress: onProgress,
            preview: emptyPreview,
            tracker: tracker,
          );
        },
      );
      expect(code, 2);
      expect(promptCalls, 0);
      expect(tracker.publishCalls, 0);
      expect(lines.join('\n'), contains('Unreleased'));
    });

    test('empty + --allow-empty publishes without calling prompt', () async {
      final tracker = _CallTracker();
      var promptCalls = 0;
      final code = await runPublishCli(
        PublishCliArgs(
          bumpKind: VersionBumpKind.minor,
          folder: tempDir.path,
          allowEmpty: true,
        ),
        writeLine: (_) {},
        isInteractive: true,
        promptEmptyUnreleased: () {
          promptCalls++;
          return EmptyUnreleasedChoice.cancel;
        },
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _FakePublisherService(
            projectRoot: tempDir.path,
            updateFolderPath: updateFolderPath,
            onProgress: onProgress,
            preview: emptyPreview,
            tracker: tracker,
            publishResult: const ReleasePublishResult(
              status: ReleasePublishStatus.success,
            ),
          );
        },
      );
      expect(code, 0);
      expect(promptCalls, 0);
      expect(tracker.publishCalls, 1);
      expect(tracker.lastProceedDespiteEmpty, isTrue);
    });

    test('non-empty Unreleased publishes normally without prompt', () async {
      final tracker = _CallTracker();
      var promptCalls = 0;
      final code = await runPublishCli(
        PublishCliArgs(
          bumpKind: VersionBumpKind.patch,
          folder: tempDir.path,
        ),
        writeLine: (_) {},
        isInteractive: true,
        promptEmptyUnreleased: () {
          promptCalls++;
          return EmptyUnreleasedChoice.cancel;
        },
        serviceFactory: ({required updateFolderPath, onProgress}) {
          return _FakePublisherService(
            projectRoot: tempDir.path,
            updateFolderPath: updateFolderPath,
            onProgress: onProgress,
            preview: filledPreview,
            tracker: tracker,
            publishResult: const ReleasePublishResult(
              status: ReleasePublishStatus.success,
            ),
          );
        },
      );
      expect(code, 0);
      expect(promptCalls, 0);
      expect(tracker.publishCalls, 1);
      expect(tracker.lastProceedDespiteEmpty, isFalse);
    });
  });
}

class _CallTracker {
  int publishCalls = 0;
  int writeInstallerCalls = 0;
  bool? lastProceedDespiteEmpty;
}

class _FakePublisherService extends ReleasePublisherService {
  _FakePublisherService({
    required super.projectRoot,
    required super.updateFolderPath,
    required this.preview,
    required this.tracker,
    super.onProgress,
    this.publishResult = const ReleasePublishResult(
      status: ReleasePublishStatus.success,
    ),
    this.writeInstallerResult = const ReleasePublishResult(
      status: ReleasePublishStatus.success,
    ),
  }) : super(
          buildReleaseDirectory: p.join(projectRoot, 'build'),
          processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
          clock: () => DateTime(2026, 7, 22),
        );

  final ReleasePublishPreview preview;
  final _CallTracker tracker;
  final ReleasePublishResult publishResult;
  final ReleasePublishResult writeInstallerResult;

  @override
  Future<ReleasePublishPreview> preparePreview(VersionBumpKind kind) async =>
      preview;

  @override
  Future<ReleasePublishResult> publish({
    required VersionBumpKind bumpKind,
    bool proceedDespiteEmptyUnreleased = false,
  }) async {
    onProgress?.call('fake progress');
    tracker.publishCalls++;
    tracker.lastProceedDespiteEmpty = proceedDespiteEmptyUnreleased;
    return publishResult;
  }

  @override
  Future<ReleasePublishResult> writeInstallerOnly() async {
    tracker.writeInstallerCalls++;
    return writeInstallerResult;
  }
}
