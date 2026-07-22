import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:call_logger/core/updates/update_installer_service.dart';
import 'package:call_logger/core/updates/update_manifest.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late Directory installDir;
  late Directory updateFolder;
  late Directory userDataDb;
  late Directory userDataImages;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('update_installer_');
    installDir = Directory(p.join(tempRoot.path, 'install'));
    updateFolder = Directory(p.join(tempRoot.path, 'updates'));
    await installDir.create(recursive: true);
    await updateFolder.create(recursive: true);

    userDataDb = Directory(p.join(installDir.path, 'Data Base'));
    userDataImages = Directory(p.join(installDir.path, 'images'));
    await userDataDb.create(recursive: true);
    await userDataImages.create(recursive: true);
    await File(p.join(userDataDb.path, 'call_logger.db')).writeAsBytes([1, 2, 3]);
    await File(p.join(userDataImages.path, 'tool.png')).writeAsBytes([4, 5]);
    await File(p.join(installDir.path, 'call_logger.exe')).writeAsBytes([0x4D, 0x5A]);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<({File zipFile, String sha, UpdateManifest manifest})> writeReleaseZip({
    required List<ArchiveFile> files,
    String version = '0.24.0',
    int build = 32,
  }) async {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(f);
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final sha = sha256.convert(bytes).toString();
    final currentDir = Directory(p.join(updateFolder.path, 'current'));
    await currentDir.create(recursive: true);
    final zipName = 'call_logger_$version.zip';
    final zipFile = File(p.join(currentDir.path, zipName));
    await zipFile.writeAsBytes(bytes, flush: true);
    final manifest = UpdateManifest(
      version: version,
      build: build,
      released: '2026-07-19',
      zipFile: zipName,
      sha256: sha,
    );
    return (zipFile: zipFile, sha: sha, manifest: manifest);
  }

  UpdateInstallerService buildService({
    required List<List<String>> launchedArgs,
    required List<String> terminations,
    String? updateFolderOverride,
    bool Function()? isDevelopmentBuild,
  }) {
    return UpdateInstallerService(
      installDirectory: installDir.path,
      resolveUpdateFolder: () async => updateFolderOverride ?? updateFolder.path,
      currentPid: () => 4242,
      clock: () => DateTime(2026, 7, 19),
      isDevelopmentBuild: isDevelopmentBuild ?? (() => false),
      launchDetached: (exe, args, {workingDirectory}) async {
        launchedArgs.add([exe, ...args]);
      },
      terminateApp: () async {
        terminations.add('terminate');
      },
    );
  }

  Future<void> assertUserDataUntouched() async {
    expect(await File(p.join(userDataDb.path, 'call_logger.db')).exists(), isTrue);
    expect(
      await File(p.join(userDataDb.path, 'call_logger.db')).readAsBytes(),
      [1, 2, 3],
    );
    expect(await File(p.join(userDataImages.path, 'tool.png')).exists(), isTrue);
    expect(
      await File(p.join(userDataImages.path, 'tool.png')).readAsBytes(),
      [4, 5],
    );
  }

  test('dev build refuses prepare and leaves install folder untouched', () async {
    final released = await writeReleaseZip(files: [
      ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A]),
    ]);

    final before = await _listRelativeFiles(installDir);
    final service = buildService(
      launchedArgs: [],
      terminations: [],
      isDevelopmentBuild: () => true,
    );

    final result = await service.prepareUpdate(released.manifest);

    expect(result.success, isFalse);
    expect(result.failedStep, isNotNull);
    expect(await Directory(p.join(installDir.path, '.update_staging')).exists(),
        isFalse);
    expect(await _listRelativeFiles(installDir), before);
    await assertUserDataUntouched();
  });

  test('correct SHA-256 prepares staging + script + marker WITHOUT closing app',
      () async {
    final released = await writeReleaseZip(files: [
      ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A]),
      ArchiveFile('flutter_windows.dll', 3, [1, 2, 3]),
      ArchiveFile('data/app.so', 1, [9]),
      ArchiveFile('native_assets.json', 2, [123, 125]),
    ]);

    final launched = <List<String>>[];
    final terminations = <String>[];
    final service = buildService(
      launchedArgs: launched,
      terminations: terminations,
    );

    final result = await service.prepareUpdate(released.manifest);

    expect(result.success, isTrue);
    final stagingApp = Directory(
      p.join(installDir.path, '.update_staging', 'app'),
    );
    expect(await File(p.join(stagingApp.path, 'call_logger.exe')).exists(), isTrue);
    expect(
      await File(p.join(installDir.path, '.update_staging', 'updater.cmd')).exists(),
      isTrue,
    );
    // Δείκτης εκκρεμότητας γραμμένος.
    expect(
      await File(p.join(installDir.path, '.update_pending.json')).exists(),
      isTrue,
    );
    expect(await service.hasPendingUpdate(), isTrue);
    // Η προετοιμασία ΔΕΝ κλείνει την εφαρμογή ούτε εκκινεί τον updater.
    expect(launched, isEmpty);
    expect(terminations, isEmpty);
    await assertUserDataUntouched();
  });

  test('launchPendingUpdate starts updater, terminates, removes marker', () async {
    final released = await writeReleaseZip(files: [
      ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A]),
    ]);

    final launched = <List<String>>[];
    final terminations = <String>[];
    final service = buildService(
      launchedArgs: launched,
      terminations: terminations,
    );

    await service.prepareUpdate(released.manifest);
    final result = await service.launchPendingUpdate();

    expect(result.success, isTrue);
    expect(launched, isNotEmpty);
    expect(launched.first.first.toLowerCase(), contains('updater.cmd'));
    expect(launched.first, contains('4242')); // PID
    expect(terminations, ['terminate']);
    // Ο δείκτης διαγράφεται μετά την επιτυχή εκκίνηση του updater.
    expect(
      await File(p.join(installDir.path, '.update_pending.json')).exists(),
      isFalse,
    );
    await assertUserDataUntouched();
  });

  test('applyPendingUpdateOnStartup launches when pending, skips in dev', () async {
    final released = await writeReleaseZip(files: [
      ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A]),
    ]);

    // Χωρίς εκκρεμότητα → τίποτα.
    final noPending = buildService(launchedArgs: [], terminations: []);
    expect(await applyPendingUpdateOnStartup(noPending), isFalse);

    // Με εκκρεμότητα → εφαρμόζει.
    final launched = <List<String>>[];
    final terminations = <String>[];
    final service = buildService(
      launchedArgs: launched,
      terminations: terminations,
    );
    await service.prepareUpdate(released.manifest);
    expect(await applyPendingUpdateOnStartup(service), isTrue);
    expect(launched, isNotEmpty);
    expect(terminations, ['terminate']);

    // Dev build → δεν εφαρμόζει ποτέ, ακόμη κι αν υπάρχει δείκτης.
    final devLaunched = <List<String>>[];
    final devService = buildService(
      launchedArgs: devLaunched,
      terminations: [],
      isDevelopmentBuild: () => true,
    );
    // ξαναγράψε δείκτη μέσω μη-dev service, μετά δοκίμασε με dev
    await service.prepareUpdate(released.manifest);
    expect(await applyPendingUpdateOnStartup(devService), isFalse);
    expect(devLaunched, isEmpty);
  });

  test('cancelPendingIfOlderThan: newer available cancels stale pending', () async {
    final released = await writeReleaseZip(
      files: [ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A])],
      version: '0.24.3',
    );
    final service = buildService(launchedArgs: [], terminations: []);
    await service.prepareUpdate(released.manifest);
    expect(await service.hasPendingUpdate(), isTrue);

    // Ίδια έκδοση → ΔΕΝ ακυρώνει (μένει πορτοκαλί / εκκρεμεί επανεκκίνηση).
    expect(
      await service.cancelPendingIfOlderThan(
        availableVersion: '0.24.3',
        availableBuild: released.manifest.build,
      ),
      isFalse,
    );
    expect(await service.hasPendingUpdate(), isTrue);

    // Νεότερη διαθέσιμη → ακυρώνει την εκκρεμή (η νεότερη υπερισχύει).
    expect(
      await service.cancelPendingIfOlderThan(
        availableVersion: '0.24.4',
        availableBuild: released.manifest.build + 1,
      ),
      isTrue,
    );
    expect(await service.hasPendingUpdate(), isFalse);
    expect(
      await Directory(p.join(installDir.path, '.update_staging')).exists(),
      isFalse,
    );
    await assertUserDataUntouched();
  });

  test('wrong SHA-256 aborts without changing install directory', () async {
    final released = await writeReleaseZip(files: [
      ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A]),
    ]);
    final badManifest = UpdateManifest(
      version: released.manifest.version,
      build: released.manifest.build,
      released: released.manifest.released,
      zipFile: released.manifest.zipFile,
      sha256: '0' * 64,
    );

    final before = await _listRelativeFiles(installDir);
    final service = buildService(launchedArgs: [], terminations: []);

    final result = await service.prepareUpdate(badManifest);

    expect(result.success, isFalse);
    expect(result.message!.toLowerCase(), contains('sha'));
    expect(await Directory(p.join(installDir.path, '.update_staging')).exists(),
        isFalse);
    expect(await _listRelativeFiles(installDir), before);
    await assertUserDataUntouched();
  });

  test('zip with Data Base entry is rejected by safety guard', () async {
    final released = await writeReleaseZip(files: [
      ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A]),
      ArchiveFile('Data Base/call_logger.db', 1, [7]),
    ]);

    final service = buildService(launchedArgs: [], terminations: []);

    final result = await service.prepareUpdate(released.manifest);

    expect(result.success, isFalse);
    expect(result.failedStep, contains('δικλείδα'));
    await assertUserDataUntouched();
  });

  test('zip with path escape is rejected', () async {
    final released = await writeReleaseZip(files: [
      ArchiveFile('call_logger.exe', 2, [0x4D, 0x5A]),
      ArchiveFile('../evil.dll', 1, [8]),
    ]);

    final service = buildService(launchedArgs: [], terminations: []);

    final result = await service.prepareUpdate(released.manifest);

    expect(result.success, isFalse);
    expect(result.failedStep, contains('δικλείδα'));
    await assertUserDataUntouched();
  });
}

Future<Set<String>> _listRelativeFiles(Directory root) async {
  final out = <String>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      out.add(p.relative(entity.path, from: root.path).replaceAll('\\', '/'));
    }
  }
  return out;
}
