import 'dart:io';

import 'package:call_logger/features/database/debug/publish_cli.dart';
import 'package:call_logger/features/database/debug/release_publisher_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parsePublishCliArgs', () {
    test('folder alone is enough', () {
      final result = parsePublishCliArgs([r'--folder=C:\updates']);
      expect(result.error, isNull);
      expect(result.args, isNotNull);
      expect(result.args!.folder, r'C:\updates');
      expect(result.args!.rebuild, isFalse);
    });

    test('parses --rebuild flag', () {
      final result = parsePublishCliArgs([r'--folder=C:\updates', '--rebuild']);
      expect(result.error, isNull);
      expect(result.args!.rebuild, isTrue);
    });

    // Το --bump ήταν υποχρεωτικό αλλά αγνοούνταν πάντα (το είδος αύξησης
    // προκύπτει από το Unreleased). Ρητή απόρριψη με οδηγία, ώστε να καθαριστεί
    // και το αποθηκευμένο πρότυπο εντολής, αντί για σιωπηλή ανοχή.
    test('rejects the removed --bump with an actionable message', () {
      for (final args in [
        ['--bump=minor', '--folder=/share/updates'],
        ['--bump=patch', '--folder=/x'],
        ['--bump', '--folder=/x'],
      ]) {
        final result = parsePublishCliArgs(args);
        expect(result.args, isNull, reason: args.join(' '));
        expect(result.error, contains('--bump καταργήθηκε'));
        expect(result.error, contains('Unreleased'));
      }
    });

    test('rejects missing folder', () {
      final result = parsePublishCliArgs(['--rebuild']);
      expect(result.args, isNull);
      expect(result.error, isNotNull);
    });
  });

  group('buildPublishCliCommand', () {
    test('default template carries only the folder', () {
      final cmd = buildPublishCliCommand(
        kDefaultPublishCliCommandTemplate,
        r'\\server\share\updates',
      );
      expect(
        cmd,
        r'dart run tool/publish.dart --folder="\\server\share\updates"',
      );
      expect(cmd, isNot(contains('--bump')));
    });

    test('replaces the folder placeholder in a custom template', () {
      final cmd = buildPublishCliCommand(
        'flutter pub run tool/publish.dart --folder={folder} --rebuild',
        r'D:\out',
      );
      expect(
        cmd,
        r'flutter pub run tool/publish.dart --folder=D:\out --rebuild',
      );
    });
  });

  group('kPublishCliParametersHelp', () {
    test('documents folder and rebuild, and no longer mentions bump', () {
      expect(kPublishCliParametersHelp, contains('--folder'));
      expect(kPublishCliParametersHelp, contains('--rebuild'));
      expect(kPublishCliParametersHelp, isNot(contains('--bump')));
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
      bumpKind: VersionBumpKind.patch,
    );

    const filledPreview = ReleasePublishPreview(
      currentVersion: '0.23.1',
      currentBuild: 31,
      nextVersion: '0.23.2',
      nextBuild: 32,
      unreleasedEntryCount: 2,
      hasUnreleasedEntries: true,
      bumpKind: VersionBumpKind.patch,
    );

    test('returns 0 on success when Unreleased has entries', () async {
      final lines = <String>[];
      final tracker = _CallTracker();
      final code = await runPublishCli(
        PublishCliArgs(folder: tempDir.path),
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
      expect(tracker.writeInstallerCalls, 0);
      expect(lines, isNotEmpty);
    });

    test('returns 1 on failure', () async {
      final tracker = _CallTracker();
      final code = await runPublishCli(
        PublishCliArgs(folder: tempDir.path),
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
        PublishCliArgs(folder: tempDir.path),
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
        PublishCliArgs(folder: tempDir.path),
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
      'empty Unreleased + rebuild choice calls rebuildCurrentVersion',
      () async {
        final tracker = _CallTracker();
        final code = await runPublishCli(
          PublishCliArgs(folder: tempDir.path),
          writeLine: (_) {},
          isInteractive: true,
          promptEmptyUnreleased: () => EmptyUnreleasedChoice.rebuild,
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
        expect(code, 0);
        expect(tracker.rebuildCalls, 1);
        // Η αναδημιουργία ΔΕΝ περνά από την κανονική δημοσίευση.
        expect(tracker.publishCalls, 0);
        expect(tracker.writeInstallerCalls, 0);
      },
    );

    test('--rebuild publishes without prompting, even with entries', () async {
      final tracker = _CallTracker();
      var promptCalls = 0;
      final code = await runPublishCli(
        PublishCliArgs(folder: tempDir.path, rebuild: true),
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
          );
        },
      );
      expect(code, 0);
      expect(promptCalls, 0);
      expect(tracker.rebuildCalls, 1);
      expect(tracker.publishCalls, 0);
    });

    test('empty Unreleased + non-interactive returns 2 and hints --rebuild', () async {
      final tracker = _CallTracker();
      var promptCalls = 0;
      final lines = <String>[];
      final code = await runPublishCli(
        PublishCliArgs(folder: tempDir.path),
        writeLine: lines.add,
        isInteractive: false,
        promptEmptyUnreleased: () {
          promptCalls++;
          return EmptyUnreleasedChoice.rebuild;
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
      expect(tracker.rebuildCalls, 0);
      expect(lines.join('\n'), contains('Unreleased'));
      expect(lines.join('\n'), contains('--rebuild'));
    });

    test('non-empty Unreleased publishes normally without prompt', () async {
      final tracker = _CallTracker();
      var promptCalls = 0;
      final code = await runPublishCli(
        PublishCliArgs(folder: tempDir.path),
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
    });
  });
}

class _CallTracker {
  int publishCalls = 0;
  int writeInstallerCalls = 0;
  int rebuildCalls = 0;
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
  Future<ReleasePublishPreview> preparePreview() async => preview;

  @override
  Future<ReleasePublishResult> publish() async {
    onProgress?.call('fake progress');
    tracker.publishCalls++;
    return publishResult;
  }

  @override
  Future<ReleasePublishResult> writeInstallerOnly() async {
    tracker.writeInstallerCalls++;
    return writeInstallerResult;
  }

  @override
  Future<ReleasePublishResult> rebuildCurrentVersion() async {
    tracker.rebuildCalls++;
    return const ReleasePublishResult(status: ReleasePublishStatus.success);
  }
}
