import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import 'update_check_result.dart';
import 'update_manifest.dart';

/// Έλεγχος νέας έκδοσης από κοινόχρηστο φάκελο.
///
/// Δεν πετάει ποτέ· κάθε αποτυχία επιστρέφεται με την αιτία της
/// ([UpdateCheckResult.failure]), ώστε το UI να μπορεί να την πει.
class UpdateService {
  UpdateService({
    required this.resolveUpdateFolder,
    required this.readFileAsString,
    required this.getCurrentVersion,
    Future<bool> Function(String path)? pathExists,
    this.timeout = const Duration(seconds: 3),
    bool Function()? isDevelopmentBuild,
    DateTime Function()? clock,
  }) : pathExists = pathExists ?? ((_) async => true),
       isDevelopmentBuild = isDevelopmentBuild ?? (() => false),
       clock = clock ?? DateTime.now;

  final Future<String?> Function() resolveUpdateFolder;
  final Future<String> Function(String path) readFileAsString;
  final Future<(String version, int build)> Function() getCurrentVersion;
  final Future<bool> Function(String path) pathExists;
  final Duration timeout;
  final bool Function() isDevelopmentBuild;

  /// Ρολόι για τη σφραγίδα «πότε ελέγχθηκε» — εγχύσιμο ώστε τα τεστ να μη
  /// διαβάζουν το πραγματικό.
  final DateTime Function() clock;

  /// Κάθε αποτυχία → [UpdateCheckResult.failed] χωρίς εξαίρεση προς τα έξω.
  Future<UpdateCheckResult> checkForUpdate() async {
    if (isDevelopmentBuild()) {
      return const UpdateCheckResult.none();
    }
    try {
      return await _check().timeout(
        timeout,
        onTimeout: () =>
            const UpdateCheckResult.failed(UpdateCheckFailure.timedOut),
      );
    } catch (_) {
      return const UpdateCheckResult.failed(UpdateCheckFailure.unexpected);
    }
  }

  /// Υπάρχει έτοιμο πακέτο εγκατάστασης στον φάκελο ενημερώσεων;
  ///
  /// Ανεξάρτητο από σύγκριση εκδόσεων: για επιδιόρθωση κατεστραμμένης
  /// εγκατάστασης μετράει και η ίδια έκδοση. Επιστρέφει το [UpdateManifest]
  /// αν υπάρχει `version.json` και το αντίστοιχο `.zip`· αλλιώς `null`.
  Future<UpdateManifest?> probeAvailableInstaller() async {
    if (isDevelopmentBuild()) return null;
    try {
      return await _probe().timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  Future<UpdateManifest?> _probe() async {
    final folder = (await resolveUpdateFolder())?.trim();
    if (folder == null || folder.isEmpty) return null;

    final versionPath = p.join(folder, 'current', 'version.json');
    final raw = await readFileAsString(versionPath);
    final manifest = UpdateManifest.fromJson(jsonDecode(raw));
    if (manifest == null) return null;

    final zipPath = p.join(folder, 'current', manifest.zipFile);
    if (!await pathExists(zipPath)) return null;
    return manifest;
  }

  Future<UpdateCheckResult> _check() async {
    final String? folder;
    try {
      folder = (await resolveUpdateFolder())?.trim();
    } catch (_) {
      return const UpdateCheckResult.failed(
        UpdateCheckFailure.settingsUnreadable,
      );
    }
    if (folder == null || folder.isEmpty) {
      return const UpdateCheckResult.failed(
        UpdateCheckFailure.noFolderConfigured,
      );
    }

    final versionPath = p.join(folder, 'current', 'version.json');
    final String raw;
    try {
      raw = await readFileAsString(versionPath);
    } catch (_) {
      return const UpdateCheckResult.failed(
        UpdateCheckFailure.folderUnreadable,
      );
    }
    final UpdateManifest? manifest;
    try {
      manifest = UpdateManifest.fromJson(jsonDecode(raw));
    } catch (_) {
      return const UpdateCheckResult.failed(UpdateCheckFailure.manifestInvalid);
    }
    if (manifest == null) {
      return const UpdateCheckResult.failed(UpdateCheckFailure.manifestInvalid);
    }

    final (currentVersion, currentBuild) = await getCurrentVersion();
    final cmp = UpdateManifest.compareVersions(
      versionA: currentVersion,
      buildA: currentBuild,
      versionB: manifest.version,
      buildB: manifest.build,
    );
    return UpdateCheckResult(
      updateAvailable: cmp < 0,
      latestVersion: manifest.version,
      manifest: manifest,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      checkedAt: clock(),
    );
  }
}
