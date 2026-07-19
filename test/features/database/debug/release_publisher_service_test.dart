import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:call_logger/features/database/debug/release_publisher_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late Directory projectRoot;
  late Directory updateFolder;
  late Directory releaseDir;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('release_publisher_');
    projectRoot = Directory(p.join(tempRoot.path, 'project'));
    updateFolder = Directory(p.join(tempRoot.path, 'updates'));
    releaseDir = Directory(
      p.join(projectRoot.path, 'build', 'windows', 'x64', 'runner', 'Release'),
    );
    await projectRoot.create(recursive: true);
    await updateFolder.create(recursive: true);
    await Directory(p.join(projectRoot.path, 'assets')).create(recursive: true);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<void> writeProjectFiles({
    required String changelogJson,
    required String changelogMd,
    required String pubspec,
  }) async {
    await File(p.join(projectRoot.path, 'assets', 'changelog.json'))
        .writeAsString(changelogJson);
    await File(p.join(projectRoot.path, 'CHANGELOG.md'))
        .writeAsString(changelogMd);
    await File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsString(pubspec);
  }

  Future<void> seedReleaseArtifacts() async {
    await releaseDir.create(recursive: true);
    await File(p.join(releaseDir.path, 'call_logger.exe'))
        .writeAsBytes([0x4D, 0x5A]);
    await File(p.join(releaseDir.path, 'flutter_windows.dll'))
        .writeAsBytes([1, 2, 3]);
    await File(p.join(releaseDir.path, 'call_logger.pdb'))
        .writeAsBytes([9, 9, 9]);
    await File(p.join(releaseDir.path, 'native_assets.json'))
        .writeAsString('{}');
    final dataDir = Directory(p.join(releaseDir.path, 'data'));
    await dataDir.create(recursive: true);
    await File(p.join(dataDir.path, 'app.so')).writeAsBytes([4, 5, 6]);
    // User data folders that MUST NOT be packaged.
    final dbDir = Directory(p.join(releaseDir.path, 'Data Base'));
    await dbDir.create(recursive: true);
    await File(p.join(dbDir.path, 'call_logger.db')).writeAsBytes([7]);
    final imagesDir = Directory(p.join(releaseDir.path, 'images'));
    await imagesDir.create(recursive: true);
    await File(p.join(imagesDir.path, 'tool.png')).writeAsBytes([8]);
  }

  String sampleChangelogJson({bool emptyUnreleased = false}) {
    final unreleased = emptyUnreleased
        ? {
            'version': 'Unreleased',
            'date': '',
            'added': <String>[],
            'changed': <String>[],
            'fixed': <String>[],
          }
        : {
            'version': 'Unreleased',
            'date': '',
            'added': ['Νέο feature δοκιμής'],
            'changed': <String>[],
            'fixed': <String>[],
          };
    return jsonEncode([
      unreleased,
      {
        'version': '0.23.1',
        'date': '2026-07-12',
        'added': <String>[],
        'changed': <String>[],
        'fixed': ['Παλιά διόρθωση'],
      },
    ]);
  }

  const sampleChangelogMd = '''
# Ιστορικό Αλλαγών

## [Unreleased]

### Προστέθηκε

- Νέο feature δοκιμής

## [0.23.1] - 2026-07-12

### Διορθώθηκε

- Παλιά διόρθωση
''';

  const samplePubspec = '''
name: call_logger
version: 0.23.1+31
environment:
  sdk: ^3.10.7
''';

  ReleasePublisherService buildService({
    required Future<int> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      void Function(String line)? onOutput,
    }) processRunner,
    DateTime? now,
    ZipVerificationReader? verificationReader,
    void Function(String message)? onProgress,
  }) {
    return ReleasePublisherService(
      projectRoot: projectRoot.path,
      buildReleaseDirectory: releaseDir.path,
      updateFolderPath: updateFolder.path,
      processRunner: processRunner,
      clock: () => now ?? DateTime(2026, 7, 19),
      verificationReader: verificationReader,
      onProgress: onProgress,
    );
  }

  test('empty Unreleased returns warning and does not change files', () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(emptyUnreleased: true),
      changelogMd: sampleChangelogMd.replaceAll('- Νέο feature δοκιμής', ''),
      pubspec: samplePubspec,
    );

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
    );

    final result = await service.publish(bumpKind: VersionBumpKind.patch);

    expect(result.status, ReleasePublishStatus.emptyUnreleasedWarning);
    expect(result.failedStep, isNull);
    final pubspec = await File(p.join(projectRoot.path, 'pubspec.yaml'))
        .readAsString();
    expect(pubspec, contains('version: 0.23.1+31'));
  });

  test('seals Unreleased and bumps patch with new empty Unreleased on top',
      () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );
    await seedReleaseArtifacts();

    final steps = <String>[];
    final service = buildService(
      processRunner: (exe, args, {workingDirectory, onOutput}) async {
        steps.add('$exe ${args.join(' ')}');
        return 0;
      },
    );

    final result = await service.publish(bumpKind: VersionBumpKind.patch);

    expect(result.status, ReleasePublishStatus.success);
    expect(result.newVersion, '0.23.2');
    expect(result.newBuild, 32);

    final jsonList = jsonDecode(
      await File(p.join(projectRoot.path, 'assets', 'changelog.json'))
          .readAsString(),
    ) as List<dynamic>;
    expect(jsonList.first['version'], 'Unreleased');
    expect(jsonList.first['added'], isEmpty);
    expect(jsonList[1]['version'], '0.23.2');
    expect(jsonList[1]['date'], '2026-07-19');
    expect(jsonList[1]['added'], contains('Νέο feature δοκιμής'));

    final md =
        await File(p.join(projectRoot.path, 'CHANGELOG.md')).readAsString();
    expect(md, contains('## [Unreleased]'));
    expect(md, contains('## [0.23.2] - 2026-07-19'));
    expect(
      md.indexOf('## [Unreleased]'),
      lessThan(md.indexOf('## [0.23.2] - 2026-07-19')),
    );

    final pubspec = await File(p.join(projectRoot.path, 'pubspec.yaml'))
        .readAsString();
    expect(pubspec, contains('version: 0.23.2+32'));

    expect(steps.any((s) => s.contains('flutter') && s.contains('build')),
        isTrue);
  });

  test('minor bump resets patch to 0', () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );
    await seedReleaseArtifacts();

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
    );

    final result = await service.publish(bumpKind: VersionBumpKind.minor);

    expect(result.status, ReleasePublishStatus.success);
    expect(result.newVersion, '0.24.0');
    expect(result.newBuild, 32);
    final pubspec = await File(p.join(projectRoot.path, 'pubspec.yaml'))
        .readAsString();
    expect(pubspec, contains('version: 0.24.0+32'));
  });

  test('correct step order: seal+bump before flutter build', () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );
    await seedReleaseArtifacts();

    final order = <String>[];
    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async {
        final pubspec = await File(p.join(projectRoot.path, 'pubspec.yaml'))
            .readAsString();
        order.add('build');
        expect(pubspec, contains('version: 0.23.2+32'),
            reason: 'Το bump πρέπει να έχει γίνει πριν το flutter build');
        final jsonList = jsonDecode(
          await File(p.join(projectRoot.path, 'assets', 'changelog.json'))
              .readAsString(),
        ) as List<dynamic>;
        expect(jsonList[1]['version'], '0.23.2',
            reason: 'Η σφράγιση πρέπει να έχει γίνει πριν το flutter build');
        return 0;
      },
    );

    // Hook via onProgress to observe seal — processRunner already checks.
    final result = await service.publish(bumpKind: VersionBumpKind.patch);
    expect(result.status, ReleasePublishStatus.success);
    expect(order, ['build']);
  });

  test('build failure stops without writing to update folder', () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 1,
    );

    final result = await service.publish(bumpKind: VersionBumpKind.patch);

    expect(result.status, ReleasePublishStatus.failure);
    expect(result.failedStep, isNotNull);
    expect(result.failedStep!.toLowerCase(), contains('build'));
    expect(await Directory(p.join(updateFolder.path, 'current')).exists(),
        isFalse);
    expect(
      await File(p.join(updateFolder.path, 'install_call_logger.bat')).exists(),
      isFalse,
    );
  });

  test('build failure restores project files byte-for-byte and no version.json',
      () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );
    final jsonBefore = await File(
      p.join(projectRoot.path, 'assets', 'changelog.json'),
    ).readAsBytes();
    final mdBefore =
        await File(p.join(projectRoot.path, 'CHANGELOG.md')).readAsBytes();
    final pubBefore =
        await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes();

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 1,
    );

    final result = await service.publish(bumpKind: VersionBumpKind.patch);
    expect(result.status, ReleasePublishStatus.failure);

    expect(
      await File(p.join(projectRoot.path, 'assets', 'changelog.json'))
          .readAsBytes(),
      jsonBefore,
    );
    expect(
      await File(p.join(projectRoot.path, 'CHANGELOG.md')).readAsBytes(),
      mdBefore,
    );
    expect(
      await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes(),
      pubBefore,
    );
    expect(
      await File(p.join(updateFolder.path, 'current', 'version.json')).exists(),
      isFalse,
    );
  });

  test('two consecutive build failures do not advance pubspec version',
      () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 1,
    );

    await service.publish(bumpKind: VersionBumpKind.patch);
    await service.publish(bumpKind: VersionBumpKind.patch);

    final pubspec = await File(p.join(projectRoot.path, 'pubspec.yaml'))
        .readAsString();
    expect(pubspec, contains('version: 0.23.1+31'));
  });

  test('tampered zip via verificationReader fails with rollback, no version.json',
      () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );
    await seedReleaseArtifacts();
    final jsonBefore = await File(
      p.join(projectRoot.path, 'assets', 'changelog.json'),
    ).readAsBytes();
    final pubBefore =
        await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes();

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
      verificationReader: (path) async {
        final bytes = await File(path).readAsBytes();
        return Uint8List.fromList([...bytes, 0xFF]);
      },
    );

    final result = await service.publish(bumpKind: VersionBumpKind.patch);
    expect(result.status, ReleasePublishStatus.failure);
    expect(result.failedStep, contains('επαλήθευση'));
    expect(
      await File(p.join(updateFolder.path, 'current', 'version.json')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(updateFolder.path, 'current', 'version.json.tmp'))
          .exists(),
      isFalse,
    );
    expect(
      await File(p.join(projectRoot.path, 'assets', 'changelog.json'))
          .readAsBytes(),
      jsonBefore,
    );
    expect(
      await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes(),
      pubBefore,
    );
  });

  test('successful publish writes version.json last with matching SHA',
      () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );
    await seedReleaseArtifacts();

    final progress = <String>[];
    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
      onProgress: progress.add,
    );

    final result = await service.publish(bumpKind: VersionBumpKind.patch);
    expect(result.status, ReleasePublishStatus.success);

    final versionPath =
        p.join(updateFolder.path, 'current', 'version.json');
    expect(await File(versionPath).exists(), isTrue);
    expect(
      await File(p.join(updateFolder.path, 'current', 'version.json.tmp'))
          .exists(),
      isFalse,
    );

    final zipIdx = progress.indexWhere((m) => m.contains('Εγγραφή zip'));
    final appIdx = progress.indexWhere((m) => m.contains('current/app'));
    final batIdx = progress.indexWhere((m) => m.contains('install_call_logger'));
    final verIdx = progress.indexWhere((m) => m.contains('Εγγραφή version.json'));
    expect(zipIdx, greaterThanOrEqualTo(0));
    expect(appIdx, greaterThan(zipIdx));
    expect(batIdx, greaterThan(appIdx));
    expect(verIdx, greaterThan(batIdx));

    final manifest = jsonDecode(await File(versionPath).readAsString())
        as Map<String, dynamic>;
    final zipFile = File(
      p.join(updateFolder.path, 'current', manifest['zipFile'] as String),
    );
    final sha = sha256.convert(await zipFile.readAsBytes()).toString();
    expect(manifest['sha256'], sha);
  });

  test('preparePreview returns versions and count without modifying files',
      () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );
    final jsonBefore = await File(
      p.join(projectRoot.path, 'assets', 'changelog.json'),
    ).readAsBytes();
    final mdBefore =
        await File(p.join(projectRoot.path, 'CHANGELOG.md')).readAsBytes();
    final pubBefore =
        await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes();

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async =>
          fail('preparePreview δεν πρέπει να χτίζει'),
    );

    final preview = await service.preparePreview(VersionBumpKind.patch);
    expect(preview.currentVersion, '0.23.1');
    expect(preview.currentBuild, 31);
    expect(preview.nextVersion, '0.23.2');
    expect(preview.nextBuild, 32);
    expect(preview.unreleasedEntryCount, 1);
    expect(preview.hasUnreleasedEntries, isTrue);

    expect(
      await File(p.join(projectRoot.path, 'assets', 'changelog.json'))
          .readAsBytes(),
      jsonBefore,
    );
    expect(
      await File(p.join(projectRoot.path, 'CHANGELOG.md')).readAsBytes(),
      mdBefore,
    );
    expect(
      await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes(),
      pubBefore,
    );
  });

  test('writeInstallerOnly writes bat only without touching project or app',
      () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );
    final jsonBefore = await File(
      p.join(projectRoot.path, 'assets', 'changelog.json'),
    ).readAsBytes();
    final mdBefore =
        await File(p.join(projectRoot.path, 'CHANGELOG.md')).readAsBytes();
    final pubBefore =
        await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes();

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async =>
          fail('writeInstallerOnly δεν πρέπει να χτίζει'),
    );

    final result = await service.writeInstallerOnly();
    expect(result.status, ReleasePublishStatus.success);
    expect(
      await File(p.join(updateFolder.path, 'install_call_logger.bat')).exists(),
      isTrue,
    );
    expect(
      await File(p.join(updateFolder.path, 'current', 'version.json')).exists(),
      isFalse,
    );
    expect(
      await Directory(p.join(updateFolder.path, 'current', 'app')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(projectRoot.path, 'assets', 'changelog.json'))
          .readAsBytes(),
      jsonBefore,
    );
    expect(
      await File(p.join(projectRoot.path, 'CHANGELOG.md')).readAsBytes(),
      mdBefore,
    );
    expect(
      await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes(),
      pubBefore,
    );
  });

  test('writeInstallerOnly fails on missing folder with failedStep', () async {
    final missing = Directory(p.join(tempRoot.path, 'missing_updates'));
    final service = ReleasePublisherService(
      projectRoot: projectRoot.path,
      buildReleaseDirectory: releaseDir.path,
      updateFolderPath: missing.path,
      processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
      clock: () => DateTime(2026, 7, 19),
    );

    final result = await service.writeInstallerOnly();
    expect(result.status, ReleasePublishStatus.failure);
    expect(result.failedStep, isNotNull);
    expect(result.failedStep!.toLowerCase(), contains('εγκαταστ'));
  });

  test('allowlist excludes user data; safety rejects zip with foreign entry',
      () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      changelogMd: sampleChangelogMd,
      pubspec: samplePubspec,
    );
    await seedReleaseArtifacts();

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
    );

    final result = await service.publish(bumpKind: VersionBumpKind.patch);
    expect(result.status, ReleasePublishStatus.success);

    final zipPath = p.join(
      updateFolder.path,
      'current',
      'call_logger_0.23.2.zip',
    );
    expect(await File(zipPath).exists(), isTrue);

    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.map((e) => e.name.replaceAll('\\', '/')).toList();

    expect(names.any((n) => n == 'call_logger.exe' || n.endsWith('/call_logger.exe')),
        isTrue);
    expect(names.any((n) => n.contains('flutter_windows.dll')), isTrue);
    expect(names.any((n) => n.contains('native_assets.json')), isTrue);
    expect(names.any((n) => n.contains('data/')), isTrue);
    expect(names.any((n) => n.contains('update_source.json')), isTrue);
    expect(names.any((n) => n.contains('call_logger.pdb')), isFalse);
    expect(names.any((n) => n.startsWith('Data Base/') || n.contains('/Data Base/')),
        isFalse);
    expect(names.any((n) => n.startsWith('images/') || n.contains('/images/')),
        isFalse);

    final appDir = Directory(p.join(updateFolder.path, 'current', 'app'));
    expect(await appDir.exists(), isTrue);
    expect(await File(p.join(appDir.path, 'call_logger.exe')).exists(), isTrue);
    expect(await Directory(p.join(appDir.path, 'Data Base')).exists(), isFalse);
    expect(await Directory(p.join(appDir.path, 'images')).exists(), isFalse);

    // Δικλείδα ασφαλείας: zip με ξένη εγγραφή απορρίπτεται.
    final bad = Archive();
    bad.addFile(ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A]));
    bad.addFile(ArchiveFile('Data Base/call_logger.db', 1, [1]));
    expect(
      () => ReleasePublisherService.assertZipHasNoUserData(bad),
      throwsA(isA<StateError>()),
    );
  });

  group('nextVersion', () {
    test('patch and minor bump numerically', () {
      expect(
        ReleasePublisherService.nextVersion('0.23.1', VersionBumpKind.patch),
        '0.23.2',
      );
      expect(
        ReleasePublisherService.nextVersion('0.23.1', VersionBumpKind.minor),
        '0.24.0',
      );
      expect(
        ReleasePublisherService.nextVersion('0.26.7', VersionBumpKind.patch),
        '0.26.8',
      );
      expect(
        ReleasePublisherService.nextVersion('0.26.7', VersionBumpKind.minor),
        '0.27.0',
      );
    });

    test('malformed input returned unchanged without throwing', () {
      expect(
        ReleasePublisherService.nextVersion('not-a-version', VersionBumpKind.patch),
        'not-a-version',
      );
      expect(
        ReleasePublisherService.nextVersion('1.2', VersionBumpKind.minor),
        '1.2',
      );
      expect(
        ReleasePublisherService.nextVersion('', VersionBumpKind.patch),
        '',
      );
    });
  });
}
