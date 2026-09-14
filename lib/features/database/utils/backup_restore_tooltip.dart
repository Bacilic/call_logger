import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database_helper.dart';
import '../providers/database_backup_settings_provider.dart';
import '../services/backup_zip_health.dart';
import '../services/restore_selection.dart';
import 'backup_destination_folder_validator.dart';

/// Κείμενο tooltip για το κουμπί επαναφοράς: τι υπάρχει στον φάκελο και τι
/// θα φέρει το πιο πρόσφατο αρχείο.
final backupRestoreTooltipProvider = FutureProvider<String>((ref) async {
  ref.watch(databaseBackupSettingsProvider);
  try {
    final db = await DatabaseHelper.instance.database;
    final baseName = p.basenameWithoutExtension(db.path);
    final dest = ref
        .read(databaseBackupSettingsProvider)
        .destinationDirectory
        .trim();
    return await BackupRestoreTooltipBuilder.build(
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

  /// Παρότρυνση ελεύθερης επιλογής — κλείνει κάθε μήνυμα που δεν καταλήγει σε
  /// συγκεκριμένο αρχείο. Ο φάκελος είναι διευκόλυνση, όχι περιορισμός: η
  /// επαναφορά δέχεται οποιοδήποτε αρχείο `.zip` επιλέξετε.
  static const chooseFreelyHint =
      'Μπορείτε να επιλέξετε ελεύθερα οποιοδήποτε αρχείο .zip.';

  static const fallbackMessage =
      'Δεν ήταν δυνατός ο έλεγχος του φακέλου αντιγράφων.\n$chooseFreelyHint';

  static Future<String> build({
    required String destinationDirectory,
    required String dbBaseName,
  }) async {
    final survey = await BackupDestinationFolderValidator.surveyRestorableZips(
      destinationDirectory: destinationDirectory,
      dbBaseName: dbBaseName,
    );

    switch (survey.kind) {
      case BackupFolderSurveyKind.folderNotSet:
        return 'Δεν έχει οριστεί φάκελος αντιγράφων ασφαλείας.\n'
            '$chooseFreelyHint';
      case BackupFolderSurveyKind.folderUnavailable:
        return 'Ο φάκελος αντιγράφων δεν είναι προσβάσιμος αυτή τη στιγμή.\n'
            '$chooseFreelyHint';
      case BackupFolderSurveyKind.noZipFiles:
        return 'Ο φάκελος αντιγράφων δεν έχει κανένα αρχείο .zip.\n'
            '$chooseFreelyHint';
      case BackupFolderSurveyKind.ok:
        return _describeFoundBackups(survey, dbBaseName);
    }
  }

  static Future<String> _describeFoundBackups(
    BackupFolderSurvey survey,
    String dbBaseName,
  ) async {
    final buffer = StringBuffer()
      ..writeln(countLine(survey, dbBaseName))
      ..writeln();

    final latest = survey.latestZip;
    if (latest == null) {
      buffer.write(chooseFreelyHint);
      return buffer.toString();
    }

    final stamp = survey.latestModified == null
        ? ''
        : DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(survey.latestModified!.toLocal());
    buffer.writeln(
      stamp.isEmpty
          ? 'Πιο πρόσφατο: ${p.basename(latest.path)}'
          : 'Πιο πρόσφατο: ${p.basename(latest.path)} — $stamp',
    );
    if (!survey.latestMatchesCurrentBase) {
      buffer.writeln('(δεν είναι αντίγραφο της τρέχουσας βάσης)');
    }
    final contents = await describeZipContents(latest.path);
    if (contents.problem != null) {
      buffer.writeln(contents.problem!);
    } else {
      buffer.writeln('Περιέχει:');
      for (final item in contents.labels) {
        buffer.writeln('• $item');
      }
    }
    buffer.write(chooseFreelyHint);
    return buffer.toString();
  }

  /// Η γραμμή του πλήθους — μετράει όλα, και λέει πόσα αφορούν την τρέχουσα.
  ///
  /// Η διάκριση δεν κρύβει τίποτα· απαντά στο «γιατί βλέπω 12 αρχεία ενώ
  /// θυμάμαι τρία» μετά από αλλαγή βάσης.
  static String countLine(BackupFolderSurvey survey, String dbBaseName) {
    final total = survey.totalZipCount;
    final mine = survey.matchingZipCount;
    final totalPart = total == 1
        ? '1 αντίγραφο στον φάκελο'
        : '$total αντίγραφα στον φάκελο';
    final base = dbBaseName.trim();
    if (base.isEmpty || mine == total) return totalPart;
    if (mine == 0) return '$totalPart, κανένα της βάσης «$base»';
    return '$totalPart, $mine της βάσης «$base»';
  }

  /// Τι περιέχει ένα αντίγραφο — ή γιατί δεν μπορούμε να το πούμε.
  ///
  /// Οι ίδιες λέξεις με τη λίστα επιλογής του διαλόγου επαναφοράς: ο χρήστης
  /// δεν πρέπει να μαθαίνει δύο ονόματα για το ίδιο πράγμα.
  ///
  /// **Καμία εφεδρεία δεν υπόσχεται περιεχόμενο (14/09/2026).** Ως τότε,
  /// τέσσερις δρόμοι —αρχείο που χάθηκε, zip που δεν διαβάζεται, εξαίρεση,
  /// και αρχείο χωρίς τίποτα αναγνωρίσιμο μέσα— κατέληγαν όλοι στο ίδιο
  /// «Βάση δεδομένων». Η εφεδρεία γράφτηκε για την άγνοια· σε καθεμιά από
  /// αυτές τις τέσσερις περιπτώσεις όμως **ξέρουμε**, και η απάντηση δεν
  /// είναι «βάση δεδομένων».
  static Future<BackupZipContents> describeZipContents(String zipPath) async {
    final file = File(zipPath);
    if (!await file.exists()) {
      return const BackupZipContents.unreadable('Το αρχείο δεν βρέθηκε πλέον.');
    }

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return const BackupZipContents.unreadable(
        'Το αρχείο δεν μπόρεσε να διαβαστεί.',
      );
    }

    final health = backupArchiveHealthShortMessage(
      inspectBackupArchiveBytes(bytes),
    );
    if (health != null) return BackupZipContents.unreadable(health);

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return const BackupZipContents.unreadable(
        'Το αρχείο δεν μπόρεσε να ανοίξει.',
      );
    }

    final found = <RestorePortablePart>{};
    var hasDatabase = false;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll(r'\', '/');
      final part = restorePortablePartForEntry(name);
      if (part != null) {
        found.add(part);
      } else if (name.toLowerCase().endsWith('.db')) {
        hasDatabase = true;
      }
    }

    final labels = <String>[
      if (hasDatabase) restoreDatabaseLabel,
      for (final part in RestorePortablePart.values)
        if (found.contains(part)) restorePortablePartLabel(part),
    ];
    if (labels.isEmpty) {
      return const BackupZipContents.unreadable(
        'Το αρχείο δεν περιέχει τίποτα από όσα επαναφέρονται.',
      );
    }
    return BackupZipContents.listed(labels);
  }
}

/// Τι υπόσχεται ένα αντίγραφο, ή γιατί δεν υπόσχεται τίποτα.
class BackupZipContents {
  const BackupZipContents.listed(this.labels) : problem = null;

  const BackupZipContents.unreadable(this.problem) : labels = const <String>[];

  /// Οι ετικέτες περιεχομένου — κενές όταν υπάρχει [problem].
  final List<String> labels;

  /// Μία φράση για το τι φταίει. `null` όταν το αρχείο διαβάστηκε.
  final String? problem;
}
