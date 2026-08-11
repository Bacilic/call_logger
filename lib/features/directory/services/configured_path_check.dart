import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart';
import '../../../core/database/remote_tools_repository.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/services/settings_service.dart';
import '../../database/models/database_backup_settings.dart';

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
    required this.fixLocation,
  });

  /// Πώς λέγεται η ρύθμιση για τον χρήστη («Φάκελος αντιγράφων ασφαλείας»).
  final String settingName;

  final String path;

  /// True = ζει στο `app_settings`/πίνακες της βάσης και ταξιδεύει μαζί της.
  /// False = τοπική ρύθμιση αυτού του υπολογιστή (SharedPreferences).
  final bool storedInDatabase;

  /// Πού διορθώνεται («Ρυθμίσεις → Ενημερώσεις»).
  final String fixLocation;
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

/// Απογραφή των ρυθμισμένων διαδρομών από βάση και τοπικές ρυθμίσεις.
Future<List<ConfiguredPathEntry>> loadConfiguredPathEntries() async {
  final entries = <ConfiguredPathEntry>[];

  // ---- Ρυθμίσεις ΜΕΣΑ στη βάση: ταξιδεύουν δουλειά ↔ σπίτι.
  try {
    final db = await DatabaseHelper.instance.database;
    final rawBackup = await SettingsRepository(
      db,
    ).getSetting(DatabaseBackupSettings.appSettingsKey);
    final backup = DatabaseBackupSettings.fromJsonString(rawBackup);
    entries.add(
      ConfiguredPathEntry(
        settingName: 'Φάκελος αντιγράφων ασφαλείας',
        path: backup.destinationDirectory,
        storedInDatabase: true,
        fixLocation: 'Βάση Δεδομένων → Ρυθμίσεις βάσης → Φάκελος προορισμού',
      ),
    );
  } catch (_) {
    // Χωρίς βάση δεν υπάρχουν ρυθμίσεις βάσης να ελεγχθούν.
  }

  try {
    final tools = await RemoteToolsRepository(
      DatabaseHelper.instance,
    ).getAllNonDeletedTools();
    for (final tool in tools) {
      entries.add(
        ConfiguredPathEntry(
          settingName: 'Εργαλείο απομακρυσμένης «${tool.name}»',
          path: tool.executablePath,
          storedInDatabase: true,
          fixLocation: 'Ρυθμίσεις → Εργαλεία απομακρυσμένης σύνδεσης',
        ),
      );
    }
  } catch (_) {}

  // ---- Τοπικές ρυθμίσεις: αφορούν ΜΟΝΟ αυτό το μηχάνημα/προφίλ.
  final catalogs = SettingsService().catalogs;
  entries.add(
    ConfiguredPathEntry(
      settingName: 'Φάκελος ελέγχου ενημερώσεων',
      path: (await catalogs.getUpdateFolderPath()) ?? '',
      storedInDatabase: false,
      fixLocation: 'Ρυθμίσεις → Ενημερώσεις',
    ),
  );
  entries.add(
    ConfiguredPathEntry(
      settingName: 'Πηγή λεξικού',
      path: (await catalogs.getDictionarySourcePath()) ?? '',
      storedInDatabase: false,
      fixLocation: 'Λεξικό → διαδρομές αρχείων',
    ),
  );
  // Η εξαγωγή είναι ΣΤΟΧΟΣ εγγραφής: το αρχείο δικαιολογημένα λείπει πριν
  // την πρώτη εξαγωγή — ελέγχεται ο φάκελος που θα τη δεχτεί.
  final exportPath = ((await catalogs.getDictionaryExportPath()) ?? '').trim();
  entries.add(
    ConfiguredPathEntry(
      settingName: 'Φάκελος εξαγωγής λεξικού',
      path: exportPath.isEmpty ? '' : p.dirname(exportPath),
      storedInDatabase: false,
      fixLocation: 'Λεξικό → διαδρομές αρχείων',
    ),
  );

  return entries;
}

/// Ένα κλικ: απογραφή + αξιολόγηση με τον πραγματικό έλεγχο ύπαρξης.
Future<List<ConfiguredPathEntry>> findInvalidConfiguredPaths() {
  return loadConfiguredPathEntries().then(
    (entries) =>
        evaluateConfiguredPaths(entries, configuredPathExistsOnThisMachine),
  );
}
