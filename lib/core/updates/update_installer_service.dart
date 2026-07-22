import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'update_manifest.dart';
import 'updater_script_builder.dart';

enum UpdateInstallStatus { success, failure }

class UpdateInstallResult {
  const UpdateInstallResult({
    required this.status,
    this.failedStep,
    this.message,
  });

  final UpdateInstallStatus status;
  final String? failedStep;
  final String? message;

  bool get success => status == UpdateInstallStatus.success;
}

typedef DetachedProcessLauncher = Future<void> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

typedef AppTerminator = Future<void> Function();

/// Εγκατάσταση νέας έκδοσης μέσω staging + δείκτη εκκρεμότητας + updater script.
///
/// Ροή: [prepareUpdate] ετοιμάζει το πακέτο και γράφει δείκτη εκκρεμότητας
/// (χωρίς κλείσιμο). [launchPendingUpdate] εκκινεί τον updater και κλείνει την
/// εφαρμογή. Η εκκρεμότητα εφαρμόζεται είτε άμεσα («Επανεκκίνηση τώρα») είτε
/// αυτόματα στο επόμενο άνοιγμα.
class UpdateInstallerService {
  UpdateInstallerService({
    required this.installDirectory,
    required this.resolveUpdateFolder,
    required this.launchDetached,
    required this.terminateApp,
    int Function()? currentPid,
    DateTime Function()? clock,
    bool Function()? isDevelopmentBuild,
    this.onProgress,
  })  : currentPid = currentPid ?? (() => pid),
        clock = clock ?? DateTime.now,
        isDevelopmentBuild = isDevelopmentBuild ?? (() => false);

  final String installDirectory;
  final Future<String?> Function() resolveUpdateFolder;
  final DetachedProcessLauncher launchDetached;
  final AppTerminator terminateApp;
  final int Function() currentPid;
  final DateTime Function() clock;
  final bool Function() isDevelopmentBuild;
  final void Function(String message)? onProgress;

  static const String stagingDirName = '.update_staging';
  static const String backupDirName = '.update_backup';
  static const String pendingMarkerName = '.update_pending.json';

  static const List<String> forbiddenZipPrefixes = [
    'Data Base/',
    'images/',
    'maps_images/',
    'dictionaries/',
    'logs/',
  ];

  /// Δικλείδα ασφαλείας: απαγορευμένοι φάκελοι δεδομένων + διαδρομές διαφυγής.
  static void assertZipIsSafe(Archive archive) {
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.contains('..') ||
          name.startsWith('/') ||
          RegExp(r'^[A-Za-z]:/').hasMatch(name)) {
        throw StateError(
          'Το πακετο περιεχει διαδρομη διαφυγης: $name',
        );
      }
      for (final prefix in forbiddenZipPrefixes) {
        if (name == prefix.substring(0, prefix.length - 1) ||
            name.startsWith(prefix) ||
            name.contains('/$prefix')) {
          throw StateError(
            'Το πακετο περιεχει απαγορευμενη εγγραφη δεδομενων χρηστη: $name',
          );
        }
      }
    }
  }

  File get _pendingMarkerFile =>
      File(p.join(installDirectory, pendingMarkerName));

  /// Υπάρχει έτοιμη εκκρεμής ενημέρωση (δείκτης + έγκυρο staging);
  Future<bool> hasPendingUpdate() async {
    final info = await readPendingUpdate();
    if (info == null) return false;
    final stagingExe = File(p.join(info.stagingAppPath, 'call_logger.exe'));
    return stagingExe.exists();
  }

  /// Πληροφορίες εκκρεμούς ενημέρωσης (ή null).
  Future<PendingUpdateInfo?> readPendingUpdate() async {
    try {
      final file = _pendingMarkerFile;
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final staging = raw['stagingApp'];
      final script = raw['script'];
      final backup = raw['backup'];
      final version = raw['version'];
      final build = raw['build'];
      if (staging is! String || script is! String || backup is! String) {
        return null;
      }
      return PendingUpdateInfo(
        stagingAppPath: staging,
        scriptPath: script,
        backupPath: backup,
        version: version is String ? version : '',
        build: build is int ? build : (build is num ? build.toInt() : 0),
      );
    } catch (_) {
      return null;
    }
  }

  /// Ακυρώνει την εκκρεμή ενημέρωση (διαγραφή δείκτη + staging).
  Future<void> cancelPending() async {
    try {
      if (await _pendingMarkerFile.exists()) {
        await _pendingMarkerFile.delete();
      }
    } catch (_) {}
    try {
      final staging = Directory(p.join(installDirectory, stagingDirName));
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// Αν η εκκρεμή ενημέρωση είναι ΠΑΛΙΟΤΕΡΗ από τη διαθέσιμη, ακυρώνεται (η
  /// νεότερη υπερισχύει). Επιστρέφει true αν ακυρώθηκε.
  Future<bool> cancelPendingIfOlderThan({
    required String availableVersion,
    required int availableBuild,
  }) async {
    final info = await readPendingUpdate();
    if (info == null) return false;
    final cmp = UpdateManifest.compareVersions(
      versionA: info.version,
      buildA: info.build,
      versionB: availableVersion,
      buildB: availableBuild,
    );
    if (cmp < 0) {
      await cancelPending();
      return true;
    }
    return false;
  }

  /// Προετοιμασία ενημέρωσης: staging, επαλήθευση, δείκτης εκκρεμότητας.
  /// ΔΕΝ κλείνει την εφαρμογή.
  ///
  /// [onProgressOverride] υπερισχύει του [onProgress] του στιγμιοτύπου
  /// (π.χ. ενημέρωση διαλόγου προόδου χωρίς ανακατασκευή υπηρεσίας).
  Future<UpdateInstallResult> prepareUpdate(
    UpdateManifest manifest, {
    void Function(String message)? onProgressOverride,
  }) async {
    final report = onProgressOverride ?? onProgress;
    void progress(String message) => report?.call(message);

    if (isDevelopmentBuild()) {
      return const UpdateInstallResult(
        status: UpdateInstallStatus.failure,
        failedStep: 'περιβάλλον ανάπτυξης',
        message:
            'Η εγκατάσταση ενημερώσεων δεν επιτρέπεται σε build ανάπτυξης '
            '(debug ή φάκελος build\\windows).',
      );
    }

    Directory? stagingRoot;
    try {
      final updateFolder = (await resolveUpdateFolder())?.trim();
      if (updateFolder == null || updateFolder.isEmpty) {
        return const UpdateInstallResult(
          status: UpdateInstallStatus.failure,
          failedStep: 'πηγή ενημερώσεων',
          message: 'Δεν έχει οριστεί φάκελος ενημερώσεων.',
        );
      }

      final sourceZip = File(
        p.join(updateFolder, 'current', manifest.zipFile),
      );
      if (!await sourceZip.exists()) {
        return UpdateInstallResult(
          status: UpdateInstallStatus.failure,
          failedStep: 'αντιγραφή',
          message: 'Δεν βρέθηκε το αρχείο ενημέρωσης: ${manifest.zipFile}',
        );
      }

      stagingRoot = Directory(p.join(installDirectory, stagingDirName));
      if (await stagingRoot.exists()) {
        await stagingRoot.delete(recursive: true);
      }
      await stagingRoot.create(recursive: true);

      progress('Αντιγραφή πακέτου ενημέρωσης…');
      final localZip = File(p.join(stagingRoot.path, manifest.zipFile));
      await sourceZip.copy(localZip.path);

      progress('Επαλήθευση SHA-256…');
      final bytes = await localZip.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      if (digest.toLowerCase() != manifest.sha256.toLowerCase()) {
        await stagingRoot.delete(recursive: true);
        return const UpdateInstallResult(
          status: UpdateInstallStatus.failure,
          failedStep: 'επαλήθευση SHA-256',
          message:
              'Η επαλήθευση του αρχείου ενημέρωσης απέτυχε (λάθος SHA-256). '
              'Η εγκατάσταση ακυρώθηκε χωρίς αλλαγές.',
        );
      }

      progress('Έλεγχος ασφάλειας πακέτου…');
      final archive = ZipDecoder().decodeBytes(bytes);
      try {
        assertZipIsSafe(archive);
      } catch (e) {
        await stagingRoot.delete(recursive: true);
        return UpdateInstallResult(
          status: UpdateInstallStatus.failure,
          failedStep: 'δικλείδα ασφαλείας',
          message: e.toString(),
        );
      }

      progress('Αποσυμπίεση…');
      final stagingApp = Directory(p.join(stagingRoot.path, 'app'));
      await stagingApp.create(recursive: true);
      await _extractArchive(archive, stagingApp.path);

      final backupDir = Directory(p.join(installDirectory, backupDirName));
      final scriptPath = p.join(stagingRoot.path, 'updater.cmd');
      await File(scriptPath).writeAsBytes(
        utf8.encode(UpdaterScriptBuilder.build()),
        flush: true,
      );

      progress('Καταγραφή εκκρεμότητας…');
      await _pendingMarkerFile.writeAsString(
        jsonEncode({
          'stagingApp': stagingApp.path,
          'script': scriptPath,
          'backup': backupDir.path,
          'version': manifest.version,
          'build': manifest.build,
          'preparedAt': clock().toIso8601String(),
        }),
        flush: true,
      );

      return const UpdateInstallResult(
        status: UpdateInstallStatus.success,
        message: 'Η ενημέρωση είναι έτοιμη.',
      );
    } catch (e) {
      try {
        if (stagingRoot != null && await stagingRoot.exists()) {
          await stagingRoot.delete(recursive: true);
        }
      } catch (_) {}
      return UpdateInstallResult(
        status: UpdateInstallStatus.failure,
        failedStep: 'άγνωστο',
        message: e.toString(),
      );
    }
  }

  /// Εκκινεί τον updater για την εκκρεμή ενημέρωση και κλείνει την εφαρμογή.
  ///
  /// Ο δείκτης διαγράφεται **μετά** την επιτυχή εκκίνηση του script (όχι πριν),
  /// ώστε αποτυχία εκκίνησης να αφήνει δυνατότητα επανάληψης στην επόμενη φορά.
  Future<UpdateInstallResult> launchPendingUpdate() async {
    final info = await readPendingUpdate();
    if (info == null) {
      return const UpdateInstallResult(
        status: UpdateInstallStatus.failure,
        failedStep: 'εκκρεμότητα',
        message: 'Δεν υπάρχει εκκρεμής ενημέρωση.',
      );
    }

    // Αν λείπει το ίδιο το script, ΜΗΝ διαγράψεις τον δείκτη: κράτα την
    // εκκρεμότητα για επανάληψη (το detached Process.start «πετυχαίνει» ακόμη
    // κι αν το αρχείο λείπει, οπότε ο έλεγχος πρέπει να γίνει εδώ ρητά).
    if (!await File(info.scriptPath).exists()) {
      return UpdateInstallResult(
        status: UpdateInstallStatus.failure,
        failedStep: 'εκκίνηση εγκαταστάτη',
        message: 'Δεν βρέθηκε ο updater: ${info.scriptPath}',
      );
    }

    try {
      // Το script δέχεται ΜΟΝΟ το PID· τις διαδρομές τις υπολογίζει από το
      // %~dp0 (βλ. UpdateCmdLauncher / UpdaterScriptBuilder). Έτσι διαδρομές
      // με κενά (Documents\Call Logger) δεν σπάνε τη γραμμή εντολών.
      await launchDetached(
        info.scriptPath,
        ['${currentPid()}'],
        workingDirectory: installDirectory,
      );

      // At-most-once αφού το script ξεκίνησε: αν αποτύχει το overlay, δεν
      // επαναλαμβάνεται αυτόματα σε βρόχο (μένει updater.log για διάγνωση).
      if (await _pendingMarkerFile.exists()) {
        await _pendingMarkerFile.delete();
      }
    } catch (e) {
      return UpdateInstallResult(
        status: UpdateInstallStatus.failure,
        failedStep: 'εκκίνηση εγκαταστάτη',
        message: e.toString(),
      );
    }

    await terminateApp();
    return const UpdateInstallResult(
      status: UpdateInstallStatus.success,
      message:
          'Η ενημέρωση ξεκίνησε. Η εφαρμογή θα κλείσει και θα ανοίξει ξανά.',
    );
  }

  static Future<void> _extractArchive(Archive archive, String destDir) async {
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      // Παράλειψη update_source.json στη ρίζα του zip (δεν είναι προϊόν build).
      if (name == 'update_source.json') continue;
      if (entry.isFile) {
        final out = File(p.join(destDir, name));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(
          Uint8List.fromList(entry.content),
          flush: true,
        );
      } else {
        await Directory(p.join(destDir, name)).create(recursive: true);
      }
    }
  }
}

/// Πληροφορίες έτοιμης εκκρεμούς ενημέρωσης (δείκτης `.update_pending.json`).
class PendingUpdateInfo {
  const PendingUpdateInfo({
    required this.stagingAppPath,
    required this.scriptPath,
    required this.backupPath,
    required this.version,
    required this.build,
  });

  final String stagingAppPath;
  final String scriptPath;
  final String backupPath;
  final String version;
  final int build;
}
