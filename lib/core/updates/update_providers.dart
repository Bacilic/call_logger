import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../services/settings_service.dart';
import 'build_environment.dart';
import 'update_check_result.dart';
import 'update_installer_service.dart';
import 'update_manifest.dart';
import 'update_service.dart';
import 'update_source_config.dart';

final updateSourceConfigProvider = Provider<UpdateSourceConfig>((ref) {
  return UpdateSourceConfig(
    getUserUpdateFolderPath: () => SettingsService().getUpdateFolderPath(),
  );
});

final updateServiceProvider = Provider<UpdateService>((ref) {
  final config = ref.read(updateSourceConfigProvider);
  return UpdateService(
    resolveUpdateFolder: config.resolveUpdateFolderPath,
    readFileAsString: (path) => File(path).readAsString(),
    getCurrentVersion: () async {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber.trim()) ?? 0;
      return (info.version, build);
    },
    isDevelopmentBuild: () => BuildEnvironment.isDevelopmentBuild(),
  );
});

/// Έλεγχος μία φορά στο παρασκήνιο μετά την εκκίνηση.
/// Ανανέωση μόνο με ρητή `ref.invalidate(updateCheckProvider)`.
final updateCheckProvider = FutureProvider<UpdateCheckResult>((ref) async {
  final service = ref.read(updateServiceProvider);
  final result = await service.checkForUpdate();
  // «Η νεότερη υπερισχύει»: αν βρεθεί έκδοση νεότερη από μια εκκρεμή
  // (προετοιμασμένη) ενημέρωση, ακύρωσε την εκκρεμή ώστε ο χρήστης να πάει
  // κατευθείαν στην τελευταία (η κουκίδα ξαναγίνεται κόκκινη).
  final manifest = result.manifest;
  if (result.updateAvailable && manifest != null) {
    final installer = ref.read(updateInstallerServiceProvider);
    final cancelled = await installer.cancelPendingIfOlderThan(
      availableVersion: manifest.version,
      availableBuild: manifest.build,
    );
    if (cancelled) ref.invalidate(pendingUpdateProvider);
  }
  return result;
});

/// True αν υπάρχει έτοιμη εκκρεμής ενημέρωση (σε αναμονή επανεκκίνησης).
/// Ανανέωση με `ref.invalidate(pendingUpdateProvider)` μετά από prepare.
final pendingUpdateProvider = FutureProvider<bool>((ref) async {
  return ref.read(updateInstallerServiceProvider).hasPendingUpdate();
});

/// Κατασκευή του πραγματικού installer service (κοινή για provider + startup).
UpdateInstallerService buildDefaultUpdateInstallerService() {
  final config = UpdateSourceConfig(
    getUserUpdateFolderPath: () => SettingsService().getUpdateFolderPath(),
  );
  return UpdateInstallerService(
    installDirectory: AppConfig.applicationExecutableDirectory,
    resolveUpdateFolder: config.resolveUpdateFolderPath,
    isDevelopmentBuild: () => BuildEnvironment.isDevelopmentBuild(),
    launchDetached: (exe, args, {workingDirectory}) async {
      await Process.start(
        exe,
        args,
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
    },
    terminateApp: () async {
      exit(0);
    },
  );
}

final updateInstallerServiceProvider = Provider<UpdateInstallerService>((ref) {
  return buildDefaultUpdateInstallerService();
});

/// Προετοιμασία της διαθέσιμης ενημέρωσης (staging + δείκτης εκκρεμότητας).
/// ΔΕΝ κλείνει την εφαρμογή.
Future<UpdateInstallResult> prepareAvailableUpdate(
  UpdateInstallerService base, {
  required UpdateManifest manifest,
  void Function(String message)? onProgress,
}) {
  final service = UpdateInstallerService(
    installDirectory: base.installDirectory,
    resolveUpdateFolder: base.resolveUpdateFolder,
    launchDetached: base.launchDetached,
    terminateApp: base.terminateApp,
    currentPid: base.currentPid,
    clock: base.clock,
    isDevelopmentBuild: base.isDevelopmentBuild,
    onProgress: onProgress,
  );
  return service.prepareUpdate(manifest);
}

/// Εφαρμογή εκκρεμούς ενημέρωσης στην εκκίνηση: αν υπάρχει έτοιμο πακέτο (και
/// δεν είναι build ανάπτυξης), εκκινεί τον updater και κλείνει την εφαρμογή.
/// Καλείται νωρίς στο main· επιστρέφει true αν ξεκίνησε εφαρμογή ενημέρωσης.
Future<bool> applyPendingUpdateOnStartup(UpdateInstallerService base) async {
  if (base.isDevelopmentBuild()) return false;
  if (!await base.hasPendingUpdate()) return false;
  final result = await base.launchPendingUpdate();
  return result.success;
}

/// Wrapper για το `main`: χτίζει το default service και εφαρμόζει εκκρεμότητα.
/// Επιστρέφει true αν ξεκίνησε εφαρμογή ενημέρωσης (η εφαρμογή κλείνει).
Future<bool> maybeApplyPendingUpdateOnStartup() async {
  if (!Platform.isWindows) return false;
  try {
    return await applyPendingUpdateOnStartup(
      buildDefaultUpdateInstallerService(),
    );
  } catch (_) {
    return false;
  }
}
