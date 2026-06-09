import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/portable_lamp_storage.dart';
import '../providers/database_backup_settings_provider.dart';
import 'backup_destination_folder_validator.dart';

/// Κείμενο tooltip για το κουμπί επαναφοράς (βάσει τελευταίου zip στον προορισμό).
final backupRestoreTooltipProvider = FutureProvider<String>((ref) async {
  ref.watch(databaseBackupSettingsProvider);
  try {
    final db = await DatabaseHelper.instance.database;
    final baseName = p.basenameWithoutExtension(db.path);
    final dest =
        ref.read(databaseBackupSettingsProvider).destinationDirectory.trim();
    return BackupRestoreTooltipBuilder.build(
      destinationDirectory: dest,
      dbBaseName: baseName,
    );
  } catch (_) {
    return BackupRestoreTooltipBuilder.fallbackMessage;
  }
});

/// Δημιουργία μηνύματος tooltip επαναφοράς από zip.
class BackupRestoreTooltipBuilder {
  BackupRestoreTooltipBuilder._();

  static const fallbackMessage =
      'Δεν βρέθηκε πρόσφατο αντίγραφο .zip στον φάκελο προορισμού.\n'
      'Η επαναφορά εξαρτάται από το αρχείο που θα επιλέξετε.';

  static Future<String> build({
    required String destinationDirectory,
    required String dbBaseName,
  }) async {
    final zip = await BackupDestinationFolderValidator.findLatestBackupZip(
      destinationDirectory: destinationDirectory,
      dbBaseName: dbBaseName,
    );
    if (zip == null) return fallbackMessage;

    DateTime modified;
    try {
      modified = await zip.lastModified();
    } catch (_) {
      modified = DateTime.now();
    }

    final dateStr = DateFormat('dd/MM/yyyy HH:mm', 'el_GR').format(modified);
    final items = await describeZipRestoreLabels(zip.path);

    final buffer = StringBuffer()
      ..writeln('Τελευταίο αντίγραφο στις $dateStr')
      ..writeln('Επαναφορά:');
    for (final item in items) {
      buffer.writeln('• $item');
    }
    return buffer.toString().trimRight();
  }

  /// Ετικέτες περιεχομένου που θα επαναφερθούν από συγκεκριμένο zip.
  static Future<List<String>> describeZipRestoreLabels(String zipPath) async {
    final labels = <String>['Βάση εφαρμογής'];

    final file = File(zipPath);
    if (!await file.exists()) return labels;

    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final mapsPrefix = '${BuildingMapStorage.backupZipMapsFolderName}/';
      final imagesPrefix = '${AppConfig.portableImagesDirName}/';
      final dictPrefix = '${AppConfig.portableDictionariesDirName}/';
      final lampPrefix = '${PortableLampStorage.backupZipLampDbFolderName}/';

      var hasMaps = false;
      var hasToolImages = false;
      var hasLexicon = false;
      var hasLampDb = false;
      var hasAppDb = false;

      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final name = entry.name.replaceAll('\\', '/');
        if (name.startsWith(mapsPrefix)) hasMaps = true;
        if (name.startsWith(imagesPrefix)) hasToolImages = true;
        if (name.startsWith(dictPrefix)) hasLexicon = true;
        if (name.startsWith(lampPrefix)) hasLampDb = true;
        if (name.toLowerCase().endsWith('.db') && !name.startsWith(lampPrefix)) {
          hasAppDb = true;
        }
      }

      if (!hasAppDb) {
        labels.remove('Βάση εφαρμογής');
      }
      if (hasLexicon) labels.add('Λεξικό');
      if (hasMaps) labels.add('Εικόνες Χαρτών');
      if (hasToolImages) labels.add('Εικονίδια εργαλείων');
      if (hasLampDb) labels.add('Βάση Λάμπας');

      if (labels.isEmpty) {
        labels.add('Βάση εφαρμογής');
      }
    } catch (_) {}

    return labels;
  }
}
