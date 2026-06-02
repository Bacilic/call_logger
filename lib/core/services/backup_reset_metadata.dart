import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../features/database/models/database_backup_settings.dart';
import '../../features/database/providers/database_backup_settings_provider.dart';
import '../database/database_helper.dart';

/// Στοιχεία για τον διάλογο επαναφοράς (φάκελος αντιγράφων, πιο πρόσφατο αρχείο).
class BackupResetMetadata {
  const BackupResetMetadata({
    this.destinationFolderName,
    this.latestBackupLabel,
  });

  final String? destinationFolderName;
  final String? latestBackupLabel;

  bool get hasBackupFolder =>
      destinationFolderName != null && destinationFolderName!.trim().isNotEmpty;
}

/// Διάβασμα ρυθμίσεων backup από την τρέχουσα ανοιχτή βάση (πριν το reset).
class BackupResetMetadataReader {
  BackupResetMetadataReader._();

  static Future<BackupResetMetadata> read({WidgetRef? ref}) async {
    try {
      DatabaseBackupSettings settings;
      if (ref != null) {
        await ref.read(databaseBackupSettingsProvider.notifier).load();
        settings = ref.read(databaseBackupSettingsProvider);
      } else {
        final db = await DatabaseHelper.instance.database;
        final raw = await db.query(
          'app_settings',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: [DatabaseBackupSettings.appSettingsKey],
          limit: 1,
        );
        if (raw.isEmpty) {
          return const BackupResetMetadata();
        }
        settings = DatabaseBackupSettings.fromJsonString(
          raw.first['value'] as String?,
        );
      }

      final dest = settings.destinationDirectory.trim();
      if (dest.isEmpty) {
        return const BackupResetMetadata();
      }

      final dir = Directory(dest);
      if (!await dir.exists()) {
        return BackupResetMetadata(
          destinationFolderName: p.basename(dest),
        );
      }

      DateTime? latestModified;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (!lower.endsWith('.db') && !lower.endsWith('.zip')) continue;
        final modified = await entity.lastModified();
        if (latestModified == null || modified.isAfter(latestModified)) {
          latestModified = modified;
        }
      }

      return BackupResetMetadata(
        destinationFolderName: p.basename(dest),
        latestBackupLabel: latestModified == null
            ? null
            : DateFormat('dd/MM/yyyy HH:mm').format(latestModified),
      );
    } catch (_) {
      return const BackupResetMetadata();
    }
  }
}
