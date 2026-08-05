// Κατάσταση φακέλου ενημερώσεων: τι μπορούν πραγματικά να κάνουν οι συνάδελφοι
// με αυτόν τον φάκελο — όχι απλώς αν υπάρχει και γράφεται.
//
//   flutter test test/core/updates/update_folder_status_test.dart

import 'dart:io';

import 'package:call_logger/core/updates/update_folder_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('update_folder_status_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> writeManifest(String contents) async {
    final currentDir = Directory(p.join(tempDir.path, 'current'));
    await currentDir.create(recursive: true);
    await File(p.join(currentDir.path, 'version.json')).writeAsString(contents);
  }

  const validManifest = '''
{
  "version": "0.23.1",
  "build": 31,
  "released": "2026-08-03",
  "zipFile": "call_logger_0.23.1.zip",
  "sha256": "abc"
}
''';

  Future<void> writeCompanionFiles({
    bool zip = true,
    bool app = true,
    bool installer = true,
  }) async {
    final currentDir = Directory(p.join(tempDir.path, 'current'));
    await currentDir.create(recursive: true);
    if (zip) {
      await File(
        p.join(currentDir.path, 'call_logger_0.23.1.zip'),
      ).writeAsBytes([1]);
    }
    if (app) {
      final appDir = Directory(p.join(currentDir.path, 'app'));
      await appDir.create(recursive: true);
      await File(p.join(appDir.path, 'call_logger.exe')).writeAsBytes([0x4D]);
    }
    if (installer) {
      await File(
        p.join(tempDir.path, 'install_call_logger.bat'),
      ).writeAsBytes([1]);
    }
  }

  test('fully published folder → ready, with version and greek date', () async {
    await writeManifest(validManifest);
    await writeCompanionFiles();

    final status = await inspectUpdateFolder(tempDir.path);

    expect(status.state, UpdateFolderState.ready);
    expect(status.isReady, isTrue);
    expect(status.manifest?.version, '0.23.1');
    expect(status.describe(), contains('0.23.1+31'));
    expect(status.describe(), contains('03-08-2026'));
  });

  // Το σενάριο «καταστράφηκε/χάθηκε ο φάκελος»: σήμερα φαινόταν έγκυρος.
  test('empty folder → noRelease and says nobody can install', () async {
    final status = await inspectUpdateFolder(tempDir.path);

    expect(status.state, UpdateFolderState.noRelease);
    expect(status.isReady, isFalse);
    expect(status.describe(), contains('δεν περιέχει δημοσιευμένη έκδοση'));
    expect(status.describe(), contains('εγκαταστήσει'));
  });

  test('missing folder → unavailable', () async {
    final status = await inspectUpdateFolder(
      p.join(tempDir.path, 'does_not_exist'),
    );

    expect(status.state, UpdateFolderState.unavailable);
    expect(status.isReady, isFalse);
  });

  test('empty path → unavailable without throwing', () async {
    expect(
      (await inspectUpdateFolder('   ')).state,
      UpdateFolderState.unavailable,
    );
  });

  test('broken manifest → brokenManifest', () async {
    await writeManifest('{not-json');
    await writeCompanionFiles();

    final status = await inspectUpdateFolder(tempDir.path);

    expect(status.state, UpdateFolderState.brokenManifest);
    expect(status.describe(), contains('version.json'));
  });

  test('incomplete manifest fields → brokenManifest', () async {
    await writeManifest('{"version": "0.23.1"}');

    expect(
      (await inspectUpdateFolder(tempDir.path)).state,
      UpdateFolderState.brokenManifest,
    );
  });

  test('manifest without its zip → incomplete naming the zip', () async {
    await writeManifest(validManifest);
    await writeCompanionFiles(zip: false);

    final status = await inspectUpdateFolder(tempDir.path);

    expect(status.state, UpdateFolderState.incomplete);
    expect(status.missingParts, hasLength(1));
    expect(status.describe(), contains('call_logger_0.23.1.zip'));
    expect(status.describe(), contains('0.23.1'));
  });

  test('several missing parts are listed in readable greek', () async {
    await writeManifest(validManifest);
    await writeCompanionFiles(zip: false, app: false, installer: false);

    final status = await inspectUpdateFolder(tempDir.path);

    expect(status.state, UpdateFolderState.incomplete);
    expect(status.missingParts, hasLength(3));
    // «α, β και γ» — όχι σκέτη λίστα με κόμματα.
    expect(status.describe(), contains(' και '));
    expect(status.describe(), contains('install_call_logger.bat'));
    expect(status.describe(), contains('current/app'));
  });

  test('missing installer alone → incomplete', () async {
    await writeManifest(validManifest);
    await writeCompanionFiles(installer: false);

    final status = await inspectUpdateFolder(tempDir.path);

    expect(status.state, UpdateFolderState.incomplete);
    expect(status.missingParts.single, contains('install_call_logger.bat'));
  });
}
