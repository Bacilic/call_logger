import 'dart:io';

import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('update_service_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  UpdateService buildService({
    required Future<String?> Function() resolveFolder,
    required Future<String> Function(String path) readFile,
    String currentVersion = '0.23.1',
    int currentBuild = 31,
    Duration timeout = const Duration(seconds: 3),
    bool Function()? isDevelopmentBuild,
  }) {
    return UpdateService(
      resolveUpdateFolder: resolveFolder,
      readFileAsString: readFile,
      getCurrentVersion: () async => (currentVersion, currentBuild),
      timeout: timeout,
      isDevelopmentBuild: isDevelopmentBuild ?? (() => false),
    );
  }

  test('dev build → no update and does not resolve folder or read files',
      () async {
    var resolveCalls = 0;
    var readCalls = 0;
    final service = buildService(
      resolveFolder: () async {
        resolveCalls++;
        return tempDir.path;
      },
      readFile: (path) async {
        readCalls++;
        return '{}';
      },
      isDevelopmentBuild: () => true,
    );

    final result = await service.checkForUpdate();

    expect(result.updateAvailable, isFalse);
    expect(result.manifest, isNull);
    expect(resolveCalls, 0);
    expect(readCalls, 0);
  });

  test('non-dev build keeps normal check behavior for newer version', () async {
    final currentDir = Directory(p.join(tempDir.path, 'current'));
    await currentDir.create(recursive: true);
    await File(p.join(currentDir.path, 'version.json')).writeAsString('''
{
  "version": "0.24.0",
  "build": 32,
  "released": "2026-07-19",
  "zipFile": "call_logger_0.24.0.zip",
  "sha256": "deadbeef"
}
''');

    final service = buildService(
      resolveFolder: () async => tempDir.path,
      readFile: (path) => File(path).readAsString(),
      isDevelopmentBuild: () => false,
    );

    final result = await service.checkForUpdate();

    expect(result.updateAvailable, isTrue);
    expect(result.latestVersion, '0.24.0');
  });

  test('inaccessible folder → silently no update', () async {
    final service = buildService(
      resolveFolder: () async => p.join(tempDir.path, 'missing_share'),
      readFile: (path) async => throw const FileSystemException('missing'),
    );

    final result = await service.checkForUpdate();

    expect(result.updateAvailable, isFalse);
    expect(result.manifest, isNull);
  });

  test('null config (checks disabled) → silently no update', () async {
    final service = buildService(
      resolveFolder: () async => null,
      readFile: (_) async => throw StateError('should not read'),
    );

    final result = await service.checkForUpdate();

    expect(result.updateAvailable, isFalse);
  });

  test('newer version → updateAvailable true', () async {
    final currentDir = Directory(p.join(tempDir.path, 'current'));
    await currentDir.create(recursive: true);
    final versionFile = File(p.join(currentDir.path, 'version.json'));
    await versionFile.writeAsString('''
{
  "version": "0.24.0",
  "build": 32,
  "released": "2026-07-19",
  "zipFile": "call_logger_0.24.0.zip",
  "sha256": "deadbeef"
}
''');

    final service = buildService(
      resolveFolder: () async => tempDir.path,
      readFile: (path) => File(path).readAsString(),
    );

    final result = await service.checkForUpdate();

    expect(result.updateAvailable, isTrue);
    expect(result.latestVersion, '0.24.0');
    expect(result.manifest?.build, 32);
  });

  test('same version and build → updateAvailable false', () async {
    final currentDir = Directory(p.join(tempDir.path, 'current'));
    await currentDir.create(recursive: true);
    await File(p.join(currentDir.path, 'version.json')).writeAsString('''
{
  "version": "0.23.1",
  "build": 31,
  "released": "2026-07-12",
  "zipFile": "call_logger_0.23.1.zip",
  "sha256": "abc"
}
''');

    final service = buildService(
      resolveFolder: () async => tempDir.path,
      readFile: (path) => File(path).readAsString(),
    );

    final result = await service.checkForUpdate();

    expect(result.updateAvailable, isFalse);
    expect(result, isA<UpdateCheckResult>());
  });

  test('timeout → updateAvailable false', () async {
    final service = buildService(
      resolveFolder: () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return tempDir.path;
      },
      readFile: (_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return '{}';
      },
      timeout: const Duration(milliseconds: 50),
    );

    final result = await service.checkForUpdate();

    expect(result.updateAvailable, isFalse);
  });

  test('broken JSON → silently no update', () async {
    final currentDir = Directory(p.join(tempDir.path, 'current'));
    await currentDir.create(recursive: true);
    await File(p.join(currentDir.path, 'version.json'))
        .writeAsString('{not-json');

    final service = buildService(
      resolveFolder: () async => tempDir.path,
      readFile: (path) => File(path).readAsString(),
    );

    final result = await service.checkForUpdate();

    expect(result.updateAvailable, isFalse);
  });
}
