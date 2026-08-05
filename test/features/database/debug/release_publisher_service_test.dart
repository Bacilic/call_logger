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

  // Μοναδική πηγή αλήθειας ιστορικού το assets/changelog.json — το CHANGELOG.md
  // καταργήθηκε 03/08/2026 (η παράλληλη συντήρηση δημιουργούσε ασυμφωνία).
  Future<void> writeProjectFiles({
    required String changelogJson,
    required String pubspec,
  }) async {
    await File(
      p.join(projectRoot.path, 'assets', 'changelog.json'),
    ).writeAsString(changelogJson);
    await File(p.join(projectRoot.path, 'pubspec.yaml')).writeAsString(pubspec);
  }

  Future<void> seedReleaseArtifacts() async {
    await releaseDir.create(recursive: true);
    await File(
      p.join(releaseDir.path, 'call_logger.exe'),
    ).writeAsBytes([0x4D, 0x5A]);
    await File(
      p.join(releaseDir.path, 'flutter_windows.dll'),
    ).writeAsBytes([1, 2, 3]);
    await File(
      p.join(releaseDir.path, 'call_logger.pdb'),
    ).writeAsBytes([9, 9, 9]);
    await File(
      p.join(releaseDir.path, 'native_assets.json'),
    ).writeAsString('{}');
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

  String sampleChangelogJson({
    bool emptyUnreleased = false,
    bool withAdded = true,
    List<String> improvements = const [],
    List<String> fixed = const [],
  }) {
    final unreleased = emptyUnreleased
        ? {
            'version': 'Unreleased',
            'date': '',
            'added': <String>[],
            'improvements': <String>[],
            'changed': <String>[],
            'fixed': <String>[],
          }
        : {
            'version': 'Unreleased',
            'date': '',
            'added': withAdded ? ['Νέο feature δοκιμής'] : <String>[],
            'improvements': improvements,
            'changed': <String>[],
            'fixed': fixed,
          };
    return jsonEncode([
      unreleased,
      {
        'version': '0.23.1',
        'date': '2026-07-12',
        'added': <String>[],
        'improvements': <String>['Παλιά μικροβελτίωση'],
        'changed': <String>[],
        'fixed': ['Παλιά διόρθωση'],
      },
    ]);
  }

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
    })
    processRunner,
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
      pubspec: samplePubspec,
    );

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
    );

    final result = await service.publish();

    expect(result.status, ReleasePublishStatus.emptyUnreleasedWarning);
    expect(result.failedStep, isNull);
    final pubspec = await File(
      p.join(projectRoot.path, 'pubspec.yaml'),
    ).readAsString();
    expect(pubspec, contains('version: 0.23.1+31'));
  });

  test('added → minor: creates new card and resets Unreleased', () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
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

    final result = await service.publish();

    expect(result.status, ReleasePublishStatus.success);
    expect(result.newVersion, '0.24.0');
    expect(result.newBuild, 32);

    final jsonList =
        jsonDecode(
              await File(
                p.join(projectRoot.path, 'assets', 'changelog.json'),
              ).readAsString(),
            )
            as List<dynamic>;
    expect(jsonList.first['version'], 'Unreleased');
    expect(jsonList.first['added'], isEmpty);
    expect(jsonList.first['improvements'], isEmpty);
    expect(jsonList[1]['version'], '0.24.0');
    expect(jsonList[1]['date'], '2026-07-19');
    expect(jsonList[1]['added'], contains('Νέο feature δοκιμής'));
    expect(jsonList[2]['version'], '0.23.1');

    final pubspec = await File(
      p.join(projectRoot.path, 'pubspec.yaml'),
    ).readAsString();
    expect(pubspec, contains('version: 0.24.0+32'));

    expect(
      steps.any((s) => s.contains('flutter') && s.contains('build')),
      isTrue,
    );
  });

  test(
    'only improvements/fixed → patch: renames top card and merges bullets',
    () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(
          withAdded: false,
          improvements: ['Νέα μικροβελτίωση'],
          fixed: ['Νέα διόρθωση'],
        ),
        pubspec: samplePubspec,
      );
      await seedReleaseArtifacts();

      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
      );

      final result = await service.publish();

      expect(result.status, ReleasePublishStatus.success);
      expect(result.newVersion, '0.23.2');
      expect(result.newBuild, 32);

      final jsonList =
          jsonDecode(
                await File(
                  p.join(projectRoot.path, 'assets', 'changelog.json'),
                ).readAsString(),
              )
              as List<dynamic>;
      expect(jsonList.length, 2);
      expect(jsonList.first['version'], 'Unreleased');
      expect(jsonList.first['improvements'], isEmpty);
      expect(jsonList.first['fixed'], isEmpty);
      expect(jsonList[1]['version'], '0.23.2');
      expect(jsonList[1]['date'], '2026-07-19');
      expect(
        jsonList[1]['improvements'],
        containsAll(['Παλιά μικροβελτίωση', 'Νέα μικροβελτίωση']),
      );
      expect(
        jsonList[1]['fixed'],
        containsAll(['Παλιά διόρθωση', 'Νέα διόρθωση']),
      );

      final pubspec = await File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspec, contains('version: 0.23.2+32'));
    },
  );

  test('correct step order: seal+bump before flutter build', () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      pubspec: samplePubspec,
    );
    await seedReleaseArtifacts();

    final order = <String>[];
    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async {
        final pubspec = await File(
          p.join(projectRoot.path, 'pubspec.yaml'),
        ).readAsString();
        order.add('build');
        expect(
          pubspec,
          contains('version: 0.24.0+32'),
          reason: 'Το bump πρέπει να έχει γίνει πριν το flutter build',
        );
        final jsonList =
            jsonDecode(
                  await File(
                    p.join(projectRoot.path, 'assets', 'changelog.json'),
                  ).readAsString(),
                )
                as List<dynamic>;
        expect(
          jsonList[1]['version'],
          '0.24.0',
          reason: 'Η σφράγιση πρέπει να έχει γίνει πριν το flutter build',
        );
        return 0;
      },
    );

    final result = await service.publish();
    expect(result.status, ReleasePublishStatus.success);
    expect(order, ['build']);
  });

  test('build failure stops without writing to update folder', () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      pubspec: samplePubspec,
    );

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 1,
    );

    final result = await service.publish();

    expect(result.status, ReleasePublishStatus.failure);
    expect(result.failedStep, isNotNull);
    expect(result.failedStep!.toLowerCase(), contains('build'));
    expect(
      await Directory(p.join(updateFolder.path, 'current')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(updateFolder.path, 'install_call_logger.bat')).exists(),
      isFalse,
    );
  });

  test(
    'build failure restores project files byte-for-byte and no version.json',
    () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(),
        pubspec: samplePubspec,
      );
      final jsonBefore = await File(
        p.join(projectRoot.path, 'assets', 'changelog.json'),
      ).readAsBytes();
      final pubBefore = await File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).readAsBytes();

      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async => 1,
      );

      final result = await service.publish();
      expect(result.status, ReleasePublishStatus.failure);

      expect(
        await File(
          p.join(projectRoot.path, 'assets', 'changelog.json'),
        ).readAsBytes(),
        jsonBefore,
      );
      expect(
        await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes(),
        pubBefore,
      );
      expect(
        await File(
          p.join(updateFolder.path, 'current', 'version.json'),
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'two consecutive build failures do not advance pubspec version',
    () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(),
        pubspec: samplePubspec,
      );

      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async => 1,
      );

      await service.publish();
      await service.publish();

      final pubspec = await File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspec, contains('version: 0.23.1+31'));
    },
  );

  test(
    'tampered zip via verificationReader fails with rollback, no version.json',
    () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(),
        pubspec: samplePubspec,
      );
      await seedReleaseArtifacts();
      final jsonBefore = await File(
        p.join(projectRoot.path, 'assets', 'changelog.json'),
      ).readAsBytes();
      final pubBefore = await File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).readAsBytes();

      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
        verificationReader: (path) async {
          final bytes = await File(path).readAsBytes();
          return Uint8List.fromList([...bytes, 0xFF]);
        },
      );

      final result = await service.publish();
      expect(result.status, ReleasePublishStatus.failure);
      expect(result.failedStep, contains('επαλήθευση'));
      expect(
        await File(
          p.join(updateFolder.path, 'current', 'version.json'),
        ).exists(),
        isFalse,
      );
      expect(
        await File(
          p.join(updateFolder.path, 'current', 'version.json.tmp'),
        ).exists(),
        isFalse,
      );
      expect(
        await File(
          p.join(projectRoot.path, 'assets', 'changelog.json'),
        ).readAsBytes(),
        jsonBefore,
      );
      expect(
        await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes(),
        pubBefore,
      );
    },
  );

  test(
    'successful publish writes version.json last with matching SHA',
    () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(),
        pubspec: samplePubspec,
      );
      await seedReleaseArtifacts();

      final progress = <String>[];
      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
        onProgress: progress.add,
      );

      final result = await service.publish();
      expect(result.status, ReleasePublishStatus.success);

      final versionPath = p.join(updateFolder.path, 'current', 'version.json');
      expect(await File(versionPath).exists(), isTrue);
      expect(
        await File(
          p.join(updateFolder.path, 'current', 'version.json.tmp'),
        ).exists(),
        isFalse,
      );

      final zipIdx = progress.indexWhere((m) => m.contains('Εγγραφή zip'));
      final appIdx = progress.indexWhere((m) => m.contains('current/app'));
      final batIdx = progress.indexWhere(
        (m) => m.contains('install_call_logger'),
      );
      final verIdx = progress.indexWhere(
        (m) => m.contains('Εγγραφή version.json'),
      );
      expect(zipIdx, greaterThanOrEqualTo(0));
      expect(appIdx, greaterThan(zipIdx));
      expect(batIdx, greaterThan(appIdx));
      expect(verIdx, greaterThan(batIdx));

      final manifest =
          jsonDecode(await File(versionPath).readAsString())
              as Map<String, dynamic>;
      final zipFile = File(
        p.join(updateFolder.path, 'current', manifest['zipFile'] as String),
      );
      final sha = sha256.convert(await zipFile.readAsBytes()).toString();
      expect(manifest['sha256'], sha);
    },
  );

  test(
    'preparePreview returns auto bump and count without modifying files',
    () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(),
        pubspec: samplePubspec,
      );
      final jsonBefore = await File(
        p.join(projectRoot.path, 'assets', 'changelog.json'),
      ).readAsBytes();
      final pubBefore = await File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).readAsBytes();

      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async =>
            fail('preparePreview δεν πρέπει να χτίζει'),
      );

      final preview = await service.preparePreview();
      expect(preview.currentVersion, '0.23.1');
      expect(preview.currentBuild, 31);
      expect(preview.bumpKind, VersionBumpKind.minor);
      expect(preview.nextVersion, '0.24.0');
      expect(preview.nextBuild, 32);
      expect(preview.unreleasedEntryCount, 1);
      expect(preview.hasUnreleasedEntries, isTrue);

      expect(
        await File(
          p.join(projectRoot.path, 'assets', 'changelog.json'),
        ).readAsBytes(),
        jsonBefore,
      );
      expect(
        await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes(),
        pubBefore,
      );
    },
  );

  test('preparePreview chooses patch when Unreleased has no added', () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(
        withAdded: false,
        improvements: ['μ'],
        fixed: ['δ'],
      ),
      pubspec: samplePubspec,
    );

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async =>
          fail('preparePreview δεν πρέπει να χτίζει'),
    );

    final preview = await service.preparePreview();
    expect(preview.bumpKind, VersionBumpKind.patch);
    expect(preview.nextVersion, '0.23.2');
    expect(preview.unreleasedEntryCount, 2);
  });

  test(
    'writeInstallerOnly writes bat only without touching project or app',
    () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(),
        pubspec: samplePubspec,
      );
      final jsonBefore = await File(
        p.join(projectRoot.path, 'assets', 'changelog.json'),
      ).readAsBytes();
      final pubBefore = await File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).readAsBytes();

      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async =>
            fail('writeInstallerOnly δεν πρέπει να χτίζει'),
      );

      final result = await service.writeInstallerOnly();
      expect(result.status, ReleasePublishStatus.success);
      expect(
        await File(
          p.join(updateFolder.path, 'install_call_logger.bat'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(updateFolder.path, 'current', 'version.json'),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(updateFolder.path, 'current', 'app')).exists(),
        isFalse,
      );
      expect(
        await File(
          p.join(projectRoot.path, 'assets', 'changelog.json'),
        ).readAsBytes(),
        jsonBefore,
      );
      expect(
        await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes(),
        pubBefore,
      );
    },
  );

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

  test(
    'allowlist excludes user data; safety rejects zip with foreign entry',
    () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(),
        pubspec: samplePubspec,
      );
      await seedReleaseArtifacts();

      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
      );

      final result = await service.publish();
      expect(result.status, ReleasePublishStatus.success);

      final zipPath = p.join(
        updateFolder.path,
        'current',
        'call_logger_0.24.0(32).zip',
      );
      expect(await File(zipPath).exists(), isTrue);

      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.map((e) => e.name.replaceAll('\\', '/')).toList();

      expect(
        names.any(
          (n) => n == 'call_logger.exe' || n.endsWith('/call_logger.exe'),
        ),
        isTrue,
      );
      expect(names.any((n) => n.contains('flutter_windows.dll')), isTrue);
      expect(names.any((n) => n.contains('native_assets.json')), isTrue);
      expect(names.any((n) => n.contains('data/')), isTrue);
      expect(names.any((n) => n.contains('update_source.json')), isTrue);
      expect(names.any((n) => n.contains('call_logger.pdb')), isFalse);
      expect(
        names.any(
          (n) => n.startsWith('Data Base/') || n.contains('/Data Base/'),
        ),
        isFalse,
      );
      expect(
        names.any((n) => n.startsWith('images/') || n.contains('/images/')),
        isFalse,
      );

      final appDir = Directory(p.join(updateFolder.path, 'current', 'app'));
      expect(await appDir.exists(), isTrue);
      expect(
        await File(p.join(appDir.path, 'call_logger.exe')).exists(),
        isTrue,
      );
      expect(
        await Directory(p.join(appDir.path, 'Data Base')).exists(),
        isFalse,
      );
      expect(await Directory(p.join(appDir.path, 'images')).exists(), isFalse);

      // Δικλείδα ασφαλείας: zip με ξένη εγγραφή απορρίπτεται.
      final bad = Archive();
      bad.addFile(ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A]));
      bad.addFile(ArchiveFile('Data Base/call_logger.db', 1, [1]));
      expect(
        () => ReleasePublisherService.assertZipHasNoUserData(bad),
        throwsA(isA<StateError>()),
      );
    },
  );

  group('rebuildCurrentVersion', () {
    test(
      'keeps version label and changelog untouched, bumps only the build',
      () async {
        await writeProjectFiles(
          changelogJson: sampleChangelogJson(emptyUnreleased: true),
          pubspec: samplePubspec,
        );
        await seedReleaseArtifacts();
        final changelogBefore = await File(
          p.join(projectRoot.path, 'assets', 'changelog.json'),
        ).readAsBytes();

        final progress = <String>[];
        final service = buildService(
          processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
          onProgress: progress.add,
        );

        final result = await service.rebuildCurrentVersion();

        expect(result.status, ReleasePublishStatus.success);
        // Ετικέτα ΙΔΙΑ, build +1.
        expect(result.newVersion, '0.23.1');
        expect(result.newBuild, 32);
        expect(
          await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsString(),
          contains('version: 0.23.1+32'),
        );
        // Το ιστορικό δεν αγγίχτηκε καθόλου — καμία νέα κάρτα, καμία σφράγιση.
        expect(
          await File(
            p.join(projectRoot.path, 'assets', 'changelog.json'),
          ).readAsBytes(),
          changelogBefore,
        );
        expect(progress.any((m) => m.contains('Σφράγιση changelog')), isFalse);

        // Πλήρης δημοσίευση: zip, app/, εγκαταστάτης, manifest με το νέο build.
        // Το κτίσιμο στο όνομα ξεχωρίζει το πακέτο από εκείνο του build 31.
        final currentDir = Directory(p.join(updateFolder.path, 'current'));
        expect(
          await File(
            p.join(currentDir.path, 'call_logger_0.23.1(32).zip'),
          ).exists(),
          isTrue,
        );
        expect(
          await File(p.join(currentDir.path, 'app', 'call_logger.exe')).exists(),
          isTrue,
        );
        expect(
          await File(
            p.join(updateFolder.path, 'install_call_logger.bat'),
          ).exists(),
          isTrue,
        );
        final manifest =
            jsonDecode(
                  await File(
                    p.join(currentDir.path, 'version.json'),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        expect(manifest['version'], '0.23.1');
        expect(manifest['build'], 32);
      },
    );

    // Χωρίς το κτίσιμο στο όνομα, η δεύτερη αναδημιουργία θα αντικαθιστούσε
    // σιωπηλά το πακέτο της πρώτης — και στο current/ και στο αρχείο releases/.
    test(
      'two rebuilds of the same version keep BOTH packages in releases/',
      () async {
        await writeProjectFiles(
          changelogJson: sampleChangelogJson(emptyUnreleased: true),
          pubspec: samplePubspec,
        );
        await seedReleaseArtifacts();

        final service = buildService(
          processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
        );

        final first = await service.rebuildCurrentVersion();
        final second = await service.rebuildCurrentVersion();

        expect(first.newBuild, 32);
        expect(second.newBuild, 33);
        expect(first.newVersion, second.newVersion);

        // Το αρχείο κρατά ΚΑΙ ΤΑ ΔΥΟ κτίσματα της ίδιας έκδοσης.
        final releaseDir = Directory(
          p.join(updateFolder.path, 'releases', '0.23.1'),
        );
        final archived = releaseDir
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .toList()
          ..sort();
        expect(archived, [
          'call_logger_0.23.1(32).zip',
          'call_logger_0.23.1(33).zip',
        ]);

        // Το current/ κρατά μόνο το τελευταίο — το προηγούμενο καθαρίστηκε.
        final currentDir = Directory(p.join(updateFolder.path, 'current'));
        final live = currentDir
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((n) => n.endsWith('.zip'))
            .toList();
        expect(live, ['call_logger_0.23.1(33).zip']);

        // Το manifest δείχνει στο πακέτο που όντως υπάρχει.
        final manifest =
            jsonDecode(
                  await File(
                    p.join(currentDir.path, 'version.json'),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        expect(manifest['zipFile'], 'call_logger_0.23.1(33).zip');
        expect(manifest['build'], 33);
        expect(
          await File(
            p.join(currentDir.path, manifest['zipFile'] as String),
          ).exists(),
          isTrue,
        );
      },
    );

    test('build failure restores pubspec and writes no version.json', () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(emptyUnreleased: true),
        pubspec: samplePubspec,
      );
      final pubBefore = await File(
        p.join(projectRoot.path, 'pubspec.yaml'),
      ).readAsBytes();

      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async => 1,
      );

      final result = await service.rebuildCurrentVersion();

      expect(result.status, ReleasePublishStatus.failure);
      expect(result.failedStep, contains('build'));
      expect(
        await File(p.join(projectRoot.path, 'pubspec.yaml')).readAsBytes(),
        pubBefore,
      );
      expect(
        await File(
          p.join(updateFolder.path, 'current', 'version.json'),
        ).exists(),
        isFalse,
      );
    });
  });

  test(
    'successful publish prunes old zips in current/ and keeps 5 newest '
    'releases, reporting each deletion and leaving foreign files intact',
    () async {
      await writeProjectFiles(
        changelogJson: sampleChangelogJson(),
        pubspec: samplePubspec,
      );
      await seedReleaseArtifacts();

      // Παλιά zip + ξένο αρχείο στο current/. Μπαίνουν και τα δύο σχήματα
      // ονόματος: με κτίσιμο (νέο) και χωρίς (πριν την αλλαγή) — η συντήρηση
      // πρέπει να καθαρίζει και τα δύο.
      final currentDir = Directory(p.join(updateFolder.path, 'current'));
      await currentDir.create(recursive: true);
      for (final name in [
        'call_logger_0.20.0.zip',
        'call_logger_0.21.0.zip',
        'call_logger_0.22.0.zip',
        'call_logger_0.24.0(30).zip',
        'call_logger_0.24.0(31).zip',
      ]) {
        await File(p.join(currentDir.path, name)).writeAsBytes([1]);
      }
      await File(
        p.join(currentDir.path, 'σημειώσεις.txt'),
      ).writeAsString('δικό μου');

      // 7 φάκελοι εκδόσεων + ξένος φάκελος στο releases/.
      final releasesRoot = Directory(p.join(updateFolder.path, 'releases'));
      const seededReleases = [
        '0.18.0',
        '0.19.0',
        '0.20.0',
        '0.21.0',
        '0.22.0',
        '0.23.0',
        '0.23.1',
      ];
      for (final v in seededReleases) {
        final dir = Directory(p.join(releasesRoot.path, v));
        await dir.create(recursive: true);
        await File(
          p.join(dir.path, 'call_logger_$v.zip'),
        ).writeAsBytes([1]);
      }
      await Directory(
        p.join(releasesRoot.path, 'παλιές_σημειώσεις'),
      ).create(recursive: true);

      final progress = <String>[];
      final service = buildService(
        processRunner: (_, _, {workingDirectory, onOutput}) async => 0,
        onProgress: progress.add,
      );

      final result = await service.publish(); // → 0.24.0
      expect(result.status, ReleasePublishStatus.success);

      // current/: μόνο το νέο zip· το ξένο αρχείο δεν αγγίχτηκε.
      final zipNames = currentDir
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((n) => n.endsWith('.zip'))
          .toList();
      expect(zipNames, ['call_logger_0.24.0(32).zip']);
      expect(
        await File(p.join(currentDir.path, 'σημειώσεις.txt')).exists(),
        isTrue,
      );

      // releases/: οι 5 νεότερες (μαζί με τη νέα)· ο ξένος φάκελος μένει.
      final remaining = releasesRoot
          .listSync()
          .whereType<Directory>()
          .map((d) => p.basename(d.path))
          .toSet();
      expect(remaining, {
        '0.24.0',
        '0.23.1',
        '0.23.0',
        '0.22.0',
        '0.21.0',
        'παλιές_σημειώσεις',
      });

      // Κάθε διαγραφή αναφέρεται στην πρόοδο — και στα δύο σχήματα ονόματος.
      expect(
        progress.any((m) => m.contains('current/call_logger_0.22.0.zip')),
        isTrue,
      );
      expect(
        progress.any((m) => m.contains('current/call_logger_0.24.0(31).zip')),
        isTrue,
      );
      expect(progress.any((m) => m.contains('releases/0.18.0')), isTrue);
      expect(progress.any((m) => m.contains('releases/0.19.0')), isTrue);
      expect(progress.any((m) => m.contains('releases/0.20.0')), isTrue);
    },
  );

  test('failed publish deletes nothing from the update folder', () async {
    await writeProjectFiles(
      changelogJson: sampleChangelogJson(),
      pubspec: samplePubspec,
    );

    final currentDir = Directory(p.join(updateFolder.path, 'current'));
    await currentDir.create(recursive: true);
    await File(
      p.join(currentDir.path, 'call_logger_0.20.0.zip'),
    ).writeAsBytes([1]);
    final oldRelease = Directory(p.join(updateFolder.path, 'releases', '0.1.0'));
    await oldRelease.create(recursive: true);

    final service = buildService(
      processRunner: (_, _, {workingDirectory, onOutput}) async => 1,
    );

    final result = await service.publish();
    expect(result.status, ReleasePublishStatus.failure);
    expect(
      await File(p.join(currentDir.path, 'call_logger_0.20.0.zip')).exists(),
      isTrue,
    );
    expect(await oldRelease.exists(), isTrue);
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
        ReleasePublisherService.nextVersion(
          'not-a-version',
          VersionBumpKind.patch,
        ),
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
