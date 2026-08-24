import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../features/database/models/database_backup_settings.dart';
import '../../features/database/providers/database_backup_settings_provider.dart';
import '../../features/database/services/active_backup_settings.dart';

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
        // Ίδια πύλη με τον provider — ο κλάδος χωρίς ref δεν επιτρέπεται να
        // απαντά διαφορετικά από τον κλάδο με ref.
        settings = await ActiveBackupSettings.read();
      }

      final dest = settings.destinationDirectory.trim();
      if (dest.isEmpty) {
        return const BackupResetMetadata();
      }

      final dir = Directory(dest);
      if (!await dir.exists()) {
        return BackupResetMetadata(destinationFolderName: p.basename(dest));
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
