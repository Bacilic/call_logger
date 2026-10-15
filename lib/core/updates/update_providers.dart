import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/app_config.dart';
import '../services/app_close_controller.dart';
import '../services/settings_service.dart';
import 'build_environment.dart';
import 'update_check_result.dart';
import 'update_cmd_launcher.dart';
import 'update_installer_service.dart';
import 'update_manifest.dart';
import 'update_service.dart';
import 'update_source_config.dart';

final updateSourceConfigProvider = Provider<UpdateSourceConfig>((ref) {
  return UpdateSourceConfig(
    getUserUpdateFolderPath: () =>
        SettingsService().catalogs.getUpdateFolderPath(),
  );
});

final updateServiceProvider = Provider<UpdateService>((ref) {
  final config = ref.read(updateSourceConfigProvider);
  return UpdateService(
    resolveUpdateFolder: config.resolveUpdateFolderPath,
    readFileAsString: (path) => File(path).readAsString(),
    pathExists: (path) => File(path).exists(),
    getCurrentVersion: () async {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber.trim()) ?? 0;
      return (info.version, build);
    },
    isDevelopmentBuild: () => BuildEnvironment.isDevelopmentBuild(),
  );
});

/// Προετοιμασία + άμεση εκκίνηση εγκαταστάτη (επιδιόρθωση εγκατάστασης).
Future<UpdateInstallResult> repairInstallationFromPackage(
  UpdateInstallerService installer, {
  required UpdateManifest manifest,
  void Function(String message)? onProgress,
}) async {
  final prepared = await installer.prepareUpdate(
    manifest,
    onProgressOverride: onProgress,
  );
  if (!prepared.success) return prepared;
  return installer.launchPendingUpdate();
}

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
///
/// Το [terminateApp] λέει πώς κλείνει η εφαρμογή αφού ξεκινήσει ο updater —
/// και διαφέρει ανάλογα με το **πότε**: στην εκκίνηση δεν έχει ανοίξει ακόμη
/// τίποτα ([exitBeforeAnythingOpened]), ενώ με την εφαρμογή σε λειτουργία
/// χρειάζεται το κανονικό κλείσιμο ([closeAppForUpdate]).
UpdateInstallerService buildDefaultUpdateInstallerService({
  AppTerminator terminateApp = closeAppForUpdate,
}) {
  final config = UpdateSourceConfig(
    getUserUpdateFolderPath: () =>
        SettingsService().catalogs.getUpdateFolderPath(),
  );
  return UpdateInstallerService(
    installDirectory: AppConfig.applicationExecutableDirectory,
    resolveUpdateFolder: config.resolveUpdateFolderPath,
    isDevelopmentBuild: () => BuildEnvironment.isDevelopmentBuild(),
    launchDetached: (exe, args, {workingDirectory}) async {
      // exe = updater.cmd. Εκκίνηση μέσω cmd.exe σε δική του ορατή κονσόλα
      // (μία — δείχνει την πρόοδο)· οι διαδρομές με κενά δεν σπάνε τη γραμμή
      // εντολών γιατί μόνο η διαδρομή του script μπαίνει σε εισαγωγικά.
      await UpdateCmdLauncher.launch(
        scriptPath: exe,
        scriptArgs: args,
        workingDirectory: workingDirectory,
      );
    },
    terminateApp: terminateApp,
  );
}

/// Η εφαρμογή δουλεύει: κλείνει με τον **κανονικό** τρόπο, όπως με το «Χ».
///
/// Μέχρι 15/10/2026 η «Επανεκκίνηση τώρα» τερμάτιζε επιτόπου: το σημάδι ζωής
/// έμενε πίσω και κάθε ενημέρωση γραφόταν ως «ΑΠΟΤΟΜΟ ΤΕΛΟΣ», ο χρήστης
/// φαινόταν συνδεδεμένος ως τη λήξη, η βάση δεν έκλεινε, και το αντίγραφο
/// εξόδου δεν γινόταν. Ο updater έχει ήδη ξεκινήσει και περιμένει (έως 90″)
/// να κλείσει η διεργασία· το κανονικό κλείσιμο χωρά άνετα.
///
/// Χωρίς ερώτηση για ανοιχτό διάλογο: το κλείσιμο το αποφάσισε ήδη ο χρήστης.
/// Δεν επιστρέφει ποτέ — το κλείσιμο τελειώνει με το τέλος της διεργασίας.
Future<void> closeAppForUpdate({AppCloseController? controller}) {
  (controller ?? appCloseController).handleCloseRequest();
  return Completer<void>().future;
}

/// Στην εκκίνηση, πριν ανοίξει βάση, ημερολόγιο ή παράθυρο: δεν υπάρχει τίποτα
/// να κλείσει, και ο τερματισμός γίνεται επιτόπου.
Future<void> exitBeforeAnythingOpened() async {
  exit(0);
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
  return base.prepareUpdate(manifest, onProgressOverride: onProgress);
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
      buildDefaultUpdateInstallerService(
        terminateApp: exitBeforeAnythingOpened,
      ),
    );
  } catch (_) {
    return false;
  }
}
