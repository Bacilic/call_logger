import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_repository.dart';
import '../../../core/database/operator_settings_repository.dart';
import '../../../core/database/settings_repository.dart';
import '../../../core/models/app_permission.dart';
import '../../../core/models/operator.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/permission_service.dart';
import '../models/database_backup_settings.dart';

/// **Η μία πύλη** για τις ενεργές ρυθμίσεις αντιγράφων ασφαλείας.
///
/// Από τη Φάση 2 του μηχανισμού αντιγράφων, το «δέμα» είναι **μία κοινή
/// ρύθμιση της βάσης** (`app_settings`), ίδια για όλους: ο διαχειριστής την
/// ορίζει και όποιος έχει το δικαίωμα την εκτελεί απαράλλαχτη — αλλιώς ο
/// εφεδρικός θα έπαιρνε «επίσημο» αντίγραφο με δικές του, άγνωστες ρυθμίσεις.
/// (Στο διάστημα των προφίλ το δέμα υπήρξε προσωπικό· η [read] κάνει τη
/// μετάπτωση της επιστροφής, μία φορά ανά βάση.)
///
/// Η πύλη ΔΕΝ επιβάλλει δικαίωμα — την επιβολή την κάνουν τα σημεία δράσης
/// (χρονιστής, κλείσιμο, οθόνη ρυθμίσεων), ώστε π.χ. η κατάσταση αποτυχίας
/// να γράφεται από όποιον όντως εκτέλεσε.
///
/// Συνειδητή εξαίρεση: η υπόδειξη φακέλου προορισμού **ξένης** (κλειστής)
/// βάσης (`backup_destination_hint.dart`) διαβάζει την κοινή θέση του άλλου
/// αρχείου με ωμό ερώτημα — δεν περνά από εδώ.
abstract final class ActiveBackupSettings {
  /// Σημαία «η επιστροφή στα κοινά έγινε» — ζει στη βάση, όχι στο μηχάνημα,
  /// ώστε η μετάπτωση να τρέξει **μία φορά ανά βάση**. Χωρίς σημαία, μια
  /// επόμενη ανάγνωση θα ξαναπρόωθε μπαγιάτικο προσωπικό αντίτυπο (π.χ. από
  /// μηχάνημα με παλιά έκδοση) πάνω από φρέσκια κοινή τιμή.
  static const String migrationMarkerKey =
      'database_backup_settings_shared_migration_v1';

  /// Οι ενεργές ρυθμίσεις — ποτέ `null`: χωρίς αποθηκευμένη τιμή επιστρέφονται
  /// οι προεπιλογές.
  static Future<DatabaseBackupSettings> read() async =>
      (await readWithRaw()).settings;

  /// Όπως η [read], αλλά επιστρέφει ΚΑΙ το ωμό αποθηκευμένο JSON — το
  /// «αναμενόμενο» της ατομικής δέσμευσης [tryReplace]. Η σύγκριση γίνεται
  /// πάνω στο ωμό κείμενο, όχι σε ξαναγραμμένη μορφή: JSON παλιάς έκδοσης με
  /// επιπλέον πεδία δεν κάνει roundtrip χαρακτήρα-χαρακτήρα.
  static Future<({DatabaseBackupSettings settings, String? raw})>
  readWithRaw() async {
    final db = await DatabaseHelper.instance.database;
    final settingsRepo = SettingsRepository(db);
    await _promotePersonalBundleOnce(
      settingsRepo,
      OperatorSettingsRepository(db),
      OperatorRepository(db),
    );
    final raw = await settingsRepo.getSetting(
      DatabaseBackupSettings.appSettingsKey,
    );
    return (settings: DatabaseBackupSettings.fromJsonString(raw), raw: raw);
  }

  /// Ατομική δέσμευση: γράφει τη [replacement] ΜΟΝΟ αν το αποθηκευμένο ωμό
  /// JSON είναι ακόμη το [expectedRaw] (από την [readWithRaw]). False =
  /// κάποιος άλλος πρόλαβε να γράψει — ο καλών ξαναδιαβάζει και ξανακρίνει.
  ///
  /// Έτσι δύο μηχανήματα που οφείλουν ταυτόχρονα αυτόματο αντίγραφο δεν
  /// βγάζουν ποτέ διπλό: όποιο κερδίσει τη δέσμευση προχωρά, το άλλο βλέπει
  /// στο επόμενο τικ ότι το αντίγραφο μόλις πάρθηκε.
  static Future<bool> tryReplace({
    required String? expectedRaw,
    required DatabaseBackupSettings replacement,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return SettingsRepository(db).compareAndSetSetting(
      DatabaseBackupSettings.appSettingsKey,
      expectedRaw,
      replacement.toJsonString(),
    );
  }

  /// Γράφει τις ενεργές ρυθμίσεις στην κοινή θέση.
  static Future<void> write(DatabaseBackupSettings settings) async {
    final db = await DatabaseHelper.instance.database;
    await SettingsRepository(
      db,
    ).saveSetting(DatabaseBackupSettings.appSettingsKey, settings.toJsonString());
  }

  /// Επιστροφή του δέματος στα κοινά, μία φορά ανά βάση.
  ///
  /// Προωθείται το προσωπικό αντίτυπο του πιο αρμόδιου κατόχου — αυτός το
  /// επεξεργαζόταν όσο το δέμα ήταν προσωπικό, άρα το δικό του είναι το πιο
  /// φρέσκο. Σειρά προτίμησης: ο συνδεδεμένος χρήστης αν είναι εξουσιοδοτημένος,
  /// αλλιώς διαχειριστής, αλλιώς όποιος έχει ρητό τικ πλήρους αντιγράφου.
  /// Όλα τα προσωπικά αντίτυπα σβήνονται στο τέλος — το κλειδί δεν είναι πια
  /// προσωπικό.
  static Future<void> _promotePersonalBundleOnce(
    SettingsRepository settingsRepo,
    OperatorSettingsRepository operatorSettings,
    OperatorRepository operatorRepo,
  ) async {
    final marker = await settingsRepo.getSetting(migrationMarkerKey);
    if (marker != null && marker.trim().isNotEmpty) return;

    final copies = await operatorSettings.getValuesForKey(
      DatabaseBackupSettings.appSettingsKey,
    );

    if (copies.isNotEmpty) {
      final operators = await operatorRepo.getAll();
      final byId = <int, Operator>{
        for (final op in operators)
          if (op.id != null) op.id!: op,
      };

      bool authorized(int operatorId) {
        final op = byId[operatorId];
        if (op == null) return false;
        return PermissionService.instance.can(
          AppPermission.fullBackup,
          operator: op,
        );
      }

      int? chosenId;
      final currentId = CurrentOperator.active?.id;
      if (currentId != null &&
          copies.containsKey(currentId) &&
          authorized(currentId)) {
        chosenId = currentId;
      } else {
        for (final id in copies.keys) {
          if (!authorized(id)) continue;
          if (byId[id]!.isAdmin) {
            chosenId = id;
            break;
          }
          chosenId ??= id;
        }
      }

      final chosen = chosenId == null ? null : copies[chosenId]?.trim();
      if (chosen != null && chosen.isNotEmpty) {
        await settingsRepo.saveSetting(
          DatabaseBackupSettings.appSettingsKey,
          chosen,
        );
      }
      await operatorSettings.deleteKeyForAllOperators(
        DatabaseBackupSettings.appSettingsKey,
      );
    }

    await settingsRepo.saveSetting(migrationMarkerKey, '1');
  }
}
