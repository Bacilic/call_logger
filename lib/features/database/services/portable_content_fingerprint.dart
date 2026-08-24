import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/services/building_map_storage.dart';
import '../../../core/services/portable_lamp_storage.dart';
import '../../../core/services/portable_tool_image_storage.dart';
import '../models/database_backup_settings.dart';
import '../utils/portable_backup_availability.dart';

/// Μία καταχώρηση του αποτυπώματος: είδος, όνομα, μέγεθος, ώρα τροποποίησης.
class PortableFingerprintEntry {
  const PortableFingerprintEntry({
    required this.kind,
    required this.name,
    required this.sizeBytes,
    required this.modifiedMs,
  });

  final String kind;
  final String name;
  final int sizeBytes;
  final int modifiedMs;

  String get line => '$kind|$name|$sizeBytes|$modifiedMs';
}

/// Το «δακτυλικό αποτύπωμα» των φορητών αρχείων (κατόψεις, εικονίδια, λεξικό,
/// βάση Λάμπας): ονόματα, μεγέθη και ώρες τροποποίησης — ΟΧΙ περιεχόμενο.
///
/// Κοστίζει χιλιοστά του δευτερολέπτου και απαντά στο ερώτημα της Φάσης 5:
/// «άλλαξε κάτι από όσα μπαίνουν στο πλήρες αντίγραφο;». Ίδιο αποτύπωμα ⇒
/// γρήγορο αντίγραφο (μόνο βάση)· διαφορετικό ⇒ πλήρες. Στο αποτύπωμα
/// συμμετέχουν ΜΟΝΟ τα είδη που είναι ενεργά επιλεγμένα ΚΑΙ διαθέσιμα — άρα
/// και η αλλαγή των διακοπτών αλλάζει το αποτύπωμα και πυροδοτεί πλήρες.
abstract final class PortableContentFingerprint {
  /// Υπολογισμός για τα ενεργά είδη των [settings]. Πηγή που δεν διαβάζεται
  /// (σφάλμα δίσκου) παραλείπεται σιωπηλά — το αποτύπωμα θα αλλάξει μόλις
  /// ξαναγίνει ορατή, και το πλήρες θα παρθεί τότε.
  static Future<String> compute({
    required DatabaseBackupSettings settings,
    required PortableBackupAvailability availability,
  }) async {
    final entries = <PortableFingerprintEntry>[];

    if (settings.effectiveIncludeMapImagesInBackup(availability)) {
      try {
        entries.addAll(
          await _fromFiles(
            'maps',
            await BuildingMapStorage.listPortableImageFiles(),
          ),
        );
      } catch (_) {}
    }

    if (settings.effectiveIncludeToolImages(availability)) {
      try {
        entries.addAll(
          await _fromFiles(
            'images',
            await PortableToolImageStorage.listPortableImageFiles(),
          ),
        );
      } catch (_) {}
    }

    if (settings.effectiveIncludeLexicon(availability)) {
      try {
        entries.addAll(
          await _fromDirectoryTree(
            'lexicon',
            AppConfig.portableDictionariesDirectory,
          ),
        );
      } catch (_) {}
    }

    if (settings.effectiveIncludeLampDb(availability)) {
      try {
        final lampPath = await PortableLampStorage.portableLampDbPathForBackup();
        if (lampPath != null) {
          final f = File(lampPath);
          final stat = await f.stat();
          entries.add(
            PortableFingerprintEntry(
              kind: 'lamp',
              name: p.basename(lampPath),
              sizeBytes: stat.size,
              modifiedMs: stat.modified.millisecondsSinceEpoch,
            ),
          );
        }
      } catch (_) {}
    }

    return digestOf(entries);
  }

  /// Ντετερμινιστική σύνοψη: ταξινόμηση (η σειρά ανάγνωσης του δίσκου δεν
  /// είναι εγγύηση) και FNV-1a 64-bit — δεν χρειάζεται κρυπτογραφία, μόνο
  /// σταθερή ανίχνευση αλλαγής.
  static String digestOf(List<PortableFingerprintEntry> entries) {
    final lines = entries.map((e) => e.line).toList()..sort();
    var hash = 0xcbf29ce484222325;
    for (final line in lines) {
      for (final unit in line.codeUnits) {
        hash ^= unit;
        hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
      }
      hash ^= 0x0A;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return 'v1:${lines.length}:${hash.toRadixString(16)}';
  }

  static Future<List<PortableFingerprintEntry>> _fromFiles(
    String kind,
    List<File> files,
  ) async {
    final out = <PortableFingerprintEntry>[];
    for (final f in files) {
      try {
        final stat = await f.stat();
        out.add(
          PortableFingerprintEntry(
            kind: kind,
            name: p.basename(f.path),
            sizeBytes: stat.size,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
          ),
        );
      } catch (_) {}
    }
    return out;
  }

  static Future<List<PortableFingerprintEntry>> _fromDirectoryTree(
    String kind,
    String rootPath,
  ) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return const [];
    final out = <PortableFingerprintEntry>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        out.add(
          PortableFingerprintEntry(
            kind: kind,
            name: p
                .relative(entity.path, from: rootPath)
                .replaceAll('\\', '/'),
            sizeBytes: stat.size,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
          ),
        );
      } catch (_) {}
    }
    return out;
  }
}
