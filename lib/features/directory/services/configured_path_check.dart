import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart';
import '../../../core/database/remote_tools_repository.dart';
import '../../../core/services/settings_service.dart';
import '../../database/services/active_backup_settings.dart';
import 'configured_path_scan_result.dart';
import 'path_fix_destination.dart';

/// Έλεγχος ρυθμισμένων διαδρομών: ποιες από τις διαδρομές που κουβαλούν οι
/// ρυθμίσεις ΔΕΝ υπάρχουν σε αυτό το μηχάνημα.
///
/// Οι διαδρομές ζουν σε δύο κόσμους και ο έλεγχος το λέει τίμια:
/// • **μέσα στη βάση** — ταξιδεύουν μαζί της (δουλειά ↔ σπίτι): φάκελος
///   αντιγράφων ασφαλείας, εκτελέσιμα εργαλείων απομακρυσμένης σύνδεσης·
/// • **τοπική ρύθμιση** — ανά μηχάνημα/προφίλ: φάκελος ενημερώσεων,
///   διαδρομές λεξικού.
///
/// Δικτυακές διαδρομές σε άφταστο δίκτυο ΠΕΤΑΝΕ αντί να επιστρέψουν false
/// (PathNotFoundException/errno 53) — ο έλεγχος τις πιάνει με try και τις
/// αναφέρει κι αυτές ως «δεν βρέθηκε τώρα».
///
/// Οι έλεγχοι ύπαρξης είναι ΑΣΥΓΧΡΟΝΟΙ, παράλληλοι και με ταβάνι χρόνου:
/// σε άφταστο UNC τα Windows απαντούν μετά από δευτερόλεπτα, και ένα
/// σύγχρονο existsSync θα πάγωνε τη διεπαφή για όλο αυτό το διάστημα.

/// Μία ρυθμισμένη διαδρομή προς έλεγχο.
class ConfiguredPathEntry {
  const ConfiguredPathEntry({
    required this.settingName,
    required this.path,
    required this.storedInDatabase,
    required this.fixDestination,
  });

  /// Πώς λέγεται η ρύθμιση για τον χρήστη («Φάκελος αντιγράφων ασφαλείας»).
  final String settingName;

  final String path;

  /// True = ζει στο `app_settings`/πίνακες της βάσης και ταξιδεύει μαζί της.
  /// False = τοπική ρύθμιση αυτού του υπολογιστή (SharedPreferences).
  final bool storedInDatabase;

  /// Πού διορθώνεται — και, μαζί, πού πηγαίνει το κουμπί μετάβασης.
  final PathFixDestination fixDestination;

  /// Η οδηγία που διαβάζει ο χρήστης· βγαίνει από τον ίδιο τον προορισμό,
  /// ώστε τα δύο να μην μπορούν να αποκλίνουν.
  String get fixLocation => fixDestination.label;
}

/// Καθαρή αξιολόγηση: κρατά όσες διαδρομές δεν περνούν τον [pathExists].
/// Οι έλεγχοι τρέχουν παράλληλα — κάθε αργή διαδρομή πληρώνει μόνο τον
/// εαυτό της, όχι το άθροισμα όλων.
///
/// Κενές διαδρομές δεν είναι εύρημα — «χωρίς ρύθμιση» είναι θεμιτή επιλογή.
Future<List<ConfiguredPathEntry>> evaluateConfiguredPaths(
  List<ConfiguredPathEntry> entries,
  Future<bool> Function(String path) pathExists,
) async {
  final candidates = [
    for (final entry in entries)
      if (entry.path.trim().isNotEmpty) entry,
  ];
  final results = await Future.wait(
    candidates.map((entry) => pathExists(entry.path.trim())),
  );
  return [
    for (var i = 0; i < candidates.length; i++)
      if (!results[i]) candidates[i],
  ];
}

/// Μέγιστη αναμονή ανά διαδρομή: άφταστο δίκτυο απαντά «δεν υπάρχω» μετά
/// από τόσο, αντί να κρατά τον έλεγχο δέσμιο των timeouts των Windows.
const Duration kConfiguredPathProbeTimeout = Duration(seconds: 3);

/// Πραγματικός έλεγχος ύπαρξης: αρχείο Ή φάκελος, ασύγχρονα (δεν μπλοκάρει
/// τη διεπαφή) και με προστασία από δικτυακές διαδρομές που πετούν ή αργούν.
Future<bool> configuredPathExistsOnThisMachine(String path) async {
  try {
    return await _existsAsFileOrDirectory(
      path,
    ).timeout(kConfiguredPathProbeTimeout);
  } catch (_) {
    // Εξαίρεση Ή λήξη χρόνου: για το «τώρα, σε αυτό το μηχάνημα» δεν υπάρχει.
    return false;
  }
}

Future<bool> _existsAsFileOrDirectory(String path) async {
  if (await File(path).exists()) return true;
  return Directory(path).exists();
}

/// Οι ομάδες διαδρομών προς έλεγχο, με το όνομα που θα δει ο χρήστης αν
/// κάποια δεν διαβαστεί.
///
/// Οι δύο πρώτες ζουν **μέσα στη βάση** και ταξιδεύουν μαζί της· η τρίτη
/// είναι τοπική. Γι' αυτό ακριβώς χωρίζονται: μια κλειδωμένη βάση χάνει τις
/// δύο πρώτες και αφήνει την τρίτη να βρεθεί μια χαρά — η κατάσταση που
/// έβγαζε ψεύτικο «όλα καθαρά».
List<ConfiguredPathGroup> configuredPathGroups() {
  return [
    ConfiguredPathGroup(
      name: 'ο φάκελος αντιγράφων ασφαλείας',
      load: () async {
        // Ο φάκελος αντιγράφων του συνδεδεμένου χρήστη — ίδια πύλη με την οθόνη.
        final backup = await ActiveBackupSettings.read();
        return [
          ConfiguredPathEntry(
            settingName: 'Φάκελος αντιγράφων ασφαλείας',
            path: backup.destinationDirectory,
            storedInDatabase: true,
            fixDestination: PathFixDestination.backupSettings,
          ),
        ];
      },
    ),
    ConfiguredPathGroup(
      name: 'τα εργαλεία απομακρυσμένης σύνδεσης',
      load: () async {
        final tools = await RemoteToolsRepository(
          DatabaseHelper.instance,
        ).getAllNonDeletedTools();
        return [
          for (final tool in tools)
            ConfiguredPathEntry(
              settingName: 'Εργαλείο απομακρυσμένης «${tool.name}»',
              path: tool.executablePath,
              storedInDatabase: true,
              fixDestination: PathFixDestination.remoteTools,
            ),
        ];
      },
    ),
    ConfiguredPathGroup(
      name: 'οι τοπικές διαδρομές (ενημερώσεις και λεξικό)',
      load: () async {
        final catalogs = SettingsService().catalogs;
        // Η εξαγωγή είναι ΣΤΟΧΟΣ εγγραφής: το αρχείο δικαιολογημένα λείπει
        // πριν την πρώτη εξαγωγή — ελέγχεται ο φάκελος που θα τη δεχτεί.
        final exportPath = ((await catalogs.getDictionaryExportPath()) ?? '')
            .trim();
        return [
          ConfiguredPathEntry(
            settingName: 'Φάκελος ελέγχου ενημερώσεων',
            path: (await catalogs.getUpdateFolderPath()) ?? '',
            storedInDatabase: false,
            fixDestination: PathFixDestination.updateFolder,
          ),
          ConfiguredPathEntry(
            settingName: 'Πηγή λεξικού',
            path: (await catalogs.getDictionarySourcePath()) ?? '',
            storedInDatabase: false,
            fixDestination: PathFixDestination.dictionaryPaths,
          ),
          ConfiguredPathEntry(
            settingName: 'Φάκελος εξαγωγής λεξικού',
            path: exportPath.isEmpty ? '' : p.dirname(exportPath),
            storedInDatabase: false,
            fixDestination: PathFixDestination.dictionaryPaths,
          ),
        ];
      },
    ),
  ];
}

/// Ένα κλικ: απογραφή + αξιολόγηση με τον πραγματικό έλεγχο ύπαρξης.
///
/// Ό,τι δεν διαβάστηκε ταξιδεύει μαζί με τα ευρήματα, ώστε η οθόνη να μη
/// μπορεί να ανακοινώσει «όλες οι διαδρομές βρέθηκαν» για ομάδα που δεν
/// κοίταξε ποτέ.
Future<ConfiguredPathScanResult> findInvalidConfiguredPaths({
  List<ConfiguredPathGroup>? groups,
  Future<bool> Function(String path)? pathExists,
}) async {
  final inventory = await collectConfiguredPaths(
    groups ?? configuredPathGroups(),
  );
  final invalid = await evaluateConfiguredPaths(
    inventory.entries,
    pathExists ?? configuredPathExistsOnThisMachine,
  );
  return ConfiguredPathScanResult(
    invalidPaths: invalid,
    uncheckedGroups: inventory.unreadableGroups,
  );
}
