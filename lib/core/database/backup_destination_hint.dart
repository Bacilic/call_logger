import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

import '../../features/database/models/database_backup_settings.dart';
import '../../features/database/providers/database_backup_settings_provider.dart';
import '../../features/database/utils/backup_destination_folder_validator.dart';
import '../config/app_config.dart';

/// Επιστρέφει τον ορισμένο φάκελο αντιγράφων αν υπάρχει και είναι έγκυρος· αλλιώς `null`.
///
/// Προτεραιότητα: Riverpod (αν δόθηκε) → υποψήφιες βάσεις (ανάγνωση `app_settings`) →
/// προεπιλεγμένη διαδρομή εφαρμογής.
Future<String?> resolveValidBackupDestinationHint({
  ProviderContainer? container,
  List<String> candidateDatabasePaths = const <String>[],
  bool includeDefaultDbPath = true,
}) async {
  final tried = <String>{};

  Future<String?> acceptIfValid(String? raw) async {
    final dest = raw?.trim() ?? '';
    if (dest.isEmpty) return null;
    final key = Platform.isWindows ? dest.toLowerCase() : dest;
    if (!tried.add(key)) return null;
    final result = await BackupDestinationFolderValidator.validate(dest);
    if (result.kind == BackupDestinationValidationKind.ok) {
      return dest;
    }
    return null;
  }

  if (container != null) {
    final fromProvider = await acceptIfValid(
      container.read(databaseBackupSettingsProvider).destinationDirectory,
    );
    if (fromProvider != null) return fromProvider;
  }

  final paths = <String>[
    ...candidateDatabasePaths,
    if (includeDefaultDbPath) AppConfig.defaultDbPath,
  ];
  for (final dbPath in paths) {
    final trimmed = dbPath.trim();
    if (trimmed.isEmpty) continue;
    final fromDb = await _readBackupDestinationFromDatabaseFile(trimmed);
    final accepted = await acceptIfValid(fromDb);
    if (accepted != null) return accepted;
  }

  return null;
}

Future<String?> _readBackupDestinationFromDatabaseFile(String dbPath) async {
  final file = File(dbPath);
  try {
    if (!file.existsSync()) return null;
  } catch (_) {
    return null;
  }

  Database? db;
  try {
    db = await openDatabase(
      p.normalize(dbPath),
      readOnly: true,
      singleInstance: false,
    );
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [DatabaseBackupSettings.appSettingsKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final settings = DatabaseBackupSettings.fromJsonString(
      rows.first['value'] as String?,
    );
    return settings.destinationDirectory.trim();
  } catch (_) {
    return null;
  } finally {
    try {
      await db?.close();
    } catch (_) {}
  }
}
