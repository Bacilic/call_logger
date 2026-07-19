import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import 'update_check_result.dart';
import 'update_manifest.dart';

/// Έλεγχος νέας έκδοσης από κοινόχρηστο φάκελο (σιωπηλή αποτυχία).
class UpdateService {
  UpdateService({
    required this.resolveUpdateFolder,
    required this.readFileAsString,
    required this.getCurrentVersion,
    this.timeout = const Duration(seconds: 3),
    bool Function()? isDevelopmentBuild,
  }) : isDevelopmentBuild = isDevelopmentBuild ?? (() => false);

  final Future<String?> Function() resolveUpdateFolder;
  final Future<String> Function(String path) readFileAsString;
  final Future<(String version, int build)> Function() getCurrentVersion;
  final Duration timeout;
  final bool Function() isDevelopmentBuild;

  /// Κάθε αποτυχία → [UpdateCheckResult.none] χωρίς εξαίρεση προς τα έξω.
  Future<UpdateCheckResult> checkForUpdate() async {
    if (isDevelopmentBuild()) {
      return const UpdateCheckResult.none();
    }
    try {
      return await _check().timeout(
        timeout,
        onTimeout: () => const UpdateCheckResult.none(),
      );
    } catch (_) {
      return const UpdateCheckResult.none();
    }
  }

  Future<UpdateCheckResult> _check() async {
    final folder = (await resolveUpdateFolder())?.trim();
    if (folder == null || folder.isEmpty) {
      return const UpdateCheckResult.none();
    }

    final versionPath = p.join(folder, 'current', 'version.json');
    final raw = await readFileAsString(versionPath);
    final decoded = jsonDecode(raw);
    final manifest = UpdateManifest.fromJson(decoded);
    if (manifest == null) {
      return const UpdateCheckResult.none();
    }

    final (currentVersion, currentBuild) = await getCurrentVersion();
    final cmp = UpdateManifest.compareVersions(
      versionA: currentVersion,
      buildA: currentBuild,
      versionB: manifest.version,
      buildB: manifest.build,
    );
    if (cmp < 0) {
      return UpdateCheckResult(
        updateAvailable: true,
        latestVersion: manifest.version,
        manifest: manifest,
      );
    }
    return UpdateCheckResult(
      updateAvailable: false,
      latestVersion: manifest.version,
      manifest: manifest,
    );
  }
}
