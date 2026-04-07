import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart';
import '../../../core/database/directory_repository.dart';
import '../../../core/services/settings_service.dart';
import '../../tasks/models/task.dart';
import '../models/database_backup_settings.dart';
import 'database_backup_service.dart';

/// Αποτέλεσμα προσπάθειας αντιγράφου πριν από επικίνδυνη ενέργεια.
enum MaintenanceBackupPrecheck {
  /// Επιτυχές αντίγραφο ή δεν απαιτήθηκε επειδή δεν ήταν ενεργό.
  ok,

  /// Απενεργοποιημένο ή άδειος προορισμός — χρειάζεται επιβεβαίωση χρήστη.
  notConfigured,

  /// Σφάλμα εκτέλεσης backup.
  failed,
}

/// Αποτέλεσμα αντικατάστασης της τρέχουσας βάσης με νέο κενό αρχείο (ίδια διαδρομή).
class ReplaceDatabaseResult {
  const ReplaceDatabaseResult._({
    required this.success,
    this.errorMessage,
    this.renameFailedFilePath,
    this.renameFailedFolder,
    this.sourceDbPathForLockDiagnostic,
  });

  const ReplaceDatabaseResult.success() : this._(success: true);

  const ReplaceDatabaseResult.failure(String message)
      : this._(success: false, errorMessage: message);

  /// Η μετονομασία απέτυχε· εμφάνιση διαδρομής και άνοιγμα φακέλου.
  const ReplaceDatabaseResult.renameFailed({
    required String filePath,
    required String folderPath,
    String? sourceDbPathForLockDiagnostic,
  }) : this._(
          success: false,
          renameFailedFilePath: filePath,
          renameFailedFolder: folderPath,
          sourceDbPathForLockDiagnostic: sourceDbPathForLockDiagnostic,
          errorMessage:
              'Δεν ήταν δυνατή η μετονομασία του τρέχοντος αρχείου (π.χ. κλειδωμένο από άλλη διεργασία).',
        );

  final bool success;
  final String? errorMessage;
  final String? renameFailedFilePath;
  final String? renameFailedFolder;
  /// Διαδρομή αρχείου πριν τη μετονομασία (για `LockDiagnosticService`).
  final String? sourceDbPathForLockDiagnostic;
}

/// Λειτουργίες συντήρησης βάσης (εκκαθάριση whitelist, VACUUM/REINDEX, νέα βάση).
class DatabaseMaintenanceService {
  DatabaseMaintenanceService();

  /// Πίνακες επιτρεπτοί για πλήρες `DELETE` / στοχευμένη εκκαθάριση (όχι κλήσεις/χρήστες κ.λπ.).
  static const Set<String> purgeableTables = {
    'audit_log',
    'tasks',
    'knowledge_base',
    'user_dictionary',
  };

  static const List<String> purgeableTablesUiOrder = [
    'audit_log',
    'tasks',
    'knowledge_base',
    'user_dictionary',
  ];

  static bool isPurgeableTable(String name) => purgeableTables.contains(name);

  /// Ξεκινά backup αν είναι ενεργό και υπάρχει προορισμός.
  Future<({MaintenanceBackupPrecheck kind, String? message})>
      runPreMaintenanceBackup() async {
    try {
      final dbBk = await DatabaseHelper.instance.database;
      final raw = await DirectoryRepository(dbBk)
          .getSetting(DatabaseBackupSettings.appSettingsKey);
      final settings = DatabaseBackupSettings.fromJsonString(raw);
      if (!settings.backupOnExit ||
          settings.destinationDirectory.trim().isEmpty) {
        return (kind: MaintenanceBackupPrecheck.notConfigured, message: null);
      }
      final r = await DatabaseBackupService.runBackup(settings);
      if (r.success) {
        return (kind: MaintenanceBackupPrecheck.ok, message: r.message);
      }
      return (
        kind: MaintenanceBackupPrecheck.failed,
        message: r.message ?? 'Άγνωστο σφάλμα αντιγράφου.',
      );
    } catch (e) {
      return (
        kind: MaintenanceBackupPrecheck.failed,
        message: e.toString(),
      );
    }
  }

  Future<void> runVacuum() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('VACUUM');
  }

  Future<void> runReindex() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('REINDEX');
  }

  /// Πλήρες άδειασμα επιτρεπτού πίνακα (`DELETE FROM`, όχι `DROP`).
  Future<int> clearTableFull(String tableName) async {
    if (!isPurgeableTable(tableName)) {
      throw ArgumentError('Ο πίνακας δεν επιτρέπεται για εκκαθάριση: $tableName');
    }
    final db = await DatabaseHelper.instance.database;
    return db.delete(tableName);
  }

  /// Διαγραφή εγγραφών audit με `timestamp` (ISO) παλαιότερες από [cutoff].
  Future<int> deleteAuditLogOlderThan(DateTime cutoff) async {
    if (!isPurgeableTable('audit_log')) {
      throw StateError('audit_log not purgeable');
    }
    final db = await DatabaseHelper.instance.database;
    final iso = cutoff.toIso8601String();
    return db.delete(
      'audit_log',
      where: 'timestamp < ?',
      whereArgs: [iso],
    );
  }

  /// Διαγραφή μόνο κλειστών εκκρεμοτήτων με `updated_at` πριν το [cutoff].
  Future<int> deleteClosedTasksOlderThan(DateTime cutoff) async {
    if (!isPurgeableTable('tasks')) {
      throw StateError('tasks not purgeable');
    }
    final db = await DatabaseHelper.instance.database;
    final closed = TaskStatus.closed.toDbValue;
    final iso = cutoff.toIso8601String();
    return db.delete(
      'tasks',
      where:
          'status = ? AND COALESCE(is_deleted, 0) = 0 AND COALESCE(updated_at, created_at) IS NOT NULL '
          'AND COALESCE(updated_at, created_at) < ?',
      whereArgs: [closed, iso],
    );
  }

  /// Αφαίρεση ημερολογιακών μηνών (π.χ. audit «παλαιότερα από N μήνες»).
  static DateTime subtractCalendarMonths(DateTime from, int months) {
    var y = from.year;
    var m = from.month - months;
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    var day = from.day;
    while (day > DateTime(y, m + 1, 0).day) {
      day--;
    }
    return DateTime(
      y,
      m,
      day,
      from.hour,
      from.minute,
      from.second,
      from.millisecond,
    );
  }

  /// Αντίστοιχο της οδηγίας «6 μήνες» για κλειστά tasks.
  Future<int> deleteClosedTasksOlderThanSixMonths() =>
      deleteClosedTasksOlderThan(
        subtractCalendarMonths(DateTime.now(), 6),
      );

  String _resolveUniqueBackupFileName(String directory, String desiredName) {
    var name = desiredName;
    var counter = 1;
    while (File(p.join(directory, name)).existsSync()) {
      counter++;
      final stem = p.basenameWithoutExtension(desiredName);
      final ext = p.extension(desiredName);
      name = '${stem}_$counter$ext';
    }
    return name;
  }

  /// Π.χ. `call_logger.db` → `call_logger_old_2026-03-31.db` (μοναδικό στον φάκελο).
  String _desiredOldDatabaseBackupName(String currentDbPath) {
    final stamp = _backupDateStamp();
    final stem = p.basenameWithoutExtension(currentDbPath);
    final ext = p.extension(currentDbPath);
    final base = '${stem}_old_$stamp$ext';
    return _resolveUniqueBackupFileName(p.dirname(currentDbPath), base);
  }

  Future<void> _renameSqliteBundle(String dbPath, String newMainFileName) async {
    final dir = p.dirname(dbPath);
    final newMain = p.join(dir, newMainFileName);
    final wal = '$dbPath-wal';
    final shm = '$dbPath-shm';
    final newWal = '$newMain-wal';
    final newShm = '$newMain-shm';

    await File(dbPath).rename(newMain);
    if (await File(wal).exists()) {
      await File(wal).rename(newWal);
    }
    if (await File(shm).exists()) {
      await File(shm).rename(newShm);
    }
  }

  /// Μεταφορά σε νέο αρχείο: **μόνο μετονομασία** της τρέχουσας βάσης (`όνομα_old_YYYY-MM-DD.db`),
  /// χωρίς διαγραφή της παλιάς. Αν στον στόχο υπάρχει ήδη αρχείο (και δεν είναι η τρέχουσα βάση), επιστρέφει σφάλμα.
  ///
  /// Αν ο στόχος ταυτίζεται με την ενεργή διαδρομή → [replaceCurrentDatabaseWithNew].
  Future<ReplaceDatabaseResult> createNewDatabaseAtChosenPath(
    String targetAbsolutePath,
  ) async {
    final settings = SettingsService();
    final configuredPath = (await settings.getDatabasePath()).trim();
    if (configuredPath.isEmpty) {
      return const ReplaceDatabaseResult.failure(
        'Δεν έχει οριστεί διαδρομή βάσης στις ρυθμίσεις.',
      );
    }

    final dbPath = (await DatabaseHelper.instance.database).path;
    if (!_sameResolvedPath(dbPath, configuredPath)) {
      return ReplaceDatabaseResult.failure(
        'Η ενεργή βάση (${p.basename(dbPath)}) δεν ταιριάζει με τη ρυθμισμένη διαδρομή.',
      );
    }

    final normTarget =
        p.normalize(p.absolute(targetAbsolutePath.trim()));
    if (normTarget.isEmpty) {
      return const ReplaceDatabaseResult.failure('Κενή διαδρομή προορισμού.');
    }

    if (_sameResolvedPath(normTarget, dbPath)) {
      return replaceCurrentDatabaseWithNew();
    }

    if (await File(normTarget).exists()) {
      return const ReplaceDatabaseResult.failure(
        'Στον στόχο υπάρχει ήδη αρχείο. Δεν διαγράφουμε υπάρχοντα αρχεία· '
        'μετονομάστε ή μετακινήστε το χειροκίνητα και δοκιμάστε ξανά.',
      );
    }

    final dir = p.dirname(dbPath);
    final oldName = _desiredOldDatabaseBackupName(dbPath);
    final oldFullPath = p.join(dir, oldName);
    final sourceForDiagnostic = dbPath;

    await DatabaseHelper.instance.closeConnection();

    try {
      await _renameSqliteBundle(dbPath, oldName);
    } catch (_) {
      try {
        await DatabaseHelper.instance.initializeDatabase();
      } catch (_) {}
      return ReplaceDatabaseResult.renameFailed(
        filePath: oldFullPath,
        folderPath: dir,
        sourceDbPathForLockDiagnostic: sourceForDiagnostic,
      );
    }

    try {
      await DatabaseHelper.instance.createNewDatabaseFile(normTarget);
      await settings.setDatabasePath(normTarget);
      await DatabaseHelper.instance.initializeDatabase();
    } catch (e) {
      try {
        await DatabaseHelper.instance.initializeDatabase();
      } catch (_) {}
      return ReplaceDatabaseResult.failure(
        'Αποτυχία δημιουργίας ή αποθήκευσης νέας διαδρομής: $e',
      );
    }

    return const ReplaceDatabaseResult.success();
  }

  /// Κλείνει σύνδεση, μετονομάζει τρέχον bundle σε `{όνομα}_old_YYYY-MM-DD.db`, δημιουργεί νέο κενό αρχείο στην ίδια διαδρομή ρύθμισης.
  Future<ReplaceDatabaseResult> replaceCurrentDatabaseWithNew() async {
    final settings = SettingsService();
    final configuredPath = (await settings.getDatabasePath()).trim();
    if (configuredPath.isEmpty) {
      return const ReplaceDatabaseResult.failure(
        'Δεν έχει οριστεί διαδρομή βάσης στις ρυθμίσεις.',
      );
    }

    final dbPath = (await DatabaseHelper.instance.database).path;
    if (!_sameResolvedPath(dbPath, configuredPath)) {
      return ReplaceDatabaseResult.failure(
        'Η ενεργή βάση (${p.basename(dbPath)}) δεν ταιριάζει με τη ρυθμισμένη διαδρομή.',
      );
    }

    final dir = p.dirname(dbPath);
    final oldName = _desiredOldDatabaseBackupName(dbPath);
    final oldFullPath = p.join(dir, oldName);
    final sourceForDiagnostic = dbPath;

    await DatabaseHelper.instance.closeConnection();

    try {
      await _renameSqliteBundle(dbPath, oldName);
    } catch (e) {
      try {
        await DatabaseHelper.instance.initializeDatabase();
      } catch (_) {}
      return ReplaceDatabaseResult.renameFailed(
        filePath: oldFullPath,
        folderPath: dir,
        sourceDbPathForLockDiagnostic: sourceForDiagnostic,
      );
    }

    try {
      await DatabaseHelper.instance.createNewDatabaseFile(dbPath);
    } catch (e) {
      try {
        await DatabaseHelper.instance.initializeDatabase();
      } catch (_) {}
      return ReplaceDatabaseResult.failure(
        'Μετά τη μετονομασία απέτυχε η δημιουργία νέας βάσης: $e',
      );
    }

    try {
      await DatabaseHelper.instance.initializeDatabase();
    } catch (e) {
      return ReplaceDatabaseResult.failure(
        'Η νέα βάση δημιουργήθηκε αλλά απέτυχε το άνοιγμα: $e',
      );
    }

    return const ReplaceDatabaseResult.success();
  }

  static bool _sameResolvedPath(String a, String b) {
    final na = p.normalize(a);
    final nb = p.normalize(b);
    if (Platform.isWindows) {
      return na.toLowerCase() == nb.toLowerCase();
    }
    return na == nb;
  }

  static String _backupDateStamp() {
    final n = DateTime.now();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Άνοιγμα εξερευνητή αρχείων στη θέση αρχείου (Windows: `/select`, macOS: `-R`).
  static Future<void> revealFileInExplorer(String filePath) async {
    final norm = p.normalize(filePath);
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', norm]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', norm]);
    } else {
      final dir = File(norm).parent.path;
      await Process.run('xdg-open', [dir]);
    }
  }

  static Future<void> openFolderInExplorer(String folderPath) async {
    final norm = p.normalize(folderPath);
    if (Platform.isWindows) {
      await Process.run('explorer', [norm]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [norm]);
    } else {
      await Process.run('xdg-open', [norm]);
    }
  }
}
