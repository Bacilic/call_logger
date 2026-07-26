import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Μεταδεδομένα προέλευσης αντιγράφου ασφαλείας μέσα σε `.zip`.
///
/// Η ανάγνωση είναι ανεκτική: απουσία, κενό ή άκυρο JSON → [unknown], ποτέ εξαίρεση.
class BackupZipManifest {
  const BackupZipManifest({
    this.originalDatabasePath,
    this.databaseFileName,
    this.createdAt,
    this.appVersion,
    this.schemaVersion,
    this.isKnown = true,
  });

  const BackupZipManifest.unknown()
    : originalDatabasePath = null,
      databaseFileName = null,
      createdAt = null,
      appVersion = null,
      schemaVersion = null,
      isKnown = false;

  /// Όνομα εγγραφής στη ρίζα του zip (αγνοείται από παλιότερες επαναφορές).
  static const zipEntryName = 'backup_manifest.json';

  final String? originalDatabasePath;
  final String? databaseFileName;
  final DateTime? createdAt;
  final String? appVersion;
  final int? schemaVersion;
  final bool isKnown;

  String toJsonString() {
    return jsonEncode(<String, Object?>{
      'originalDatabasePath': originalDatabasePath,
      'databaseFileName': databaseFileName,
      'createdAt': createdAt?.toUtc().toIso8601String(),
      'appVersion': appVersion,
      'schemaVersion': schemaVersion,
    });
  }

  List<int> toUtf8Bytes() => utf8.encode(toJsonString());

  static BackupZipManifest parseJson(String raw) {
    try {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const BackupZipManifest.unknown();
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return const BackupZipManifest.unknown();
      final map = Map<String, dynamic>.from(decoded);
      final path = (map['originalDatabasePath'] as String?)?.trim();
      final name = (map['databaseFileName'] as String?)?.trim();
      final app = (map['appVersion'] as String?)?.trim();
      final schema = map['schemaVersion'];
      final createdRaw = map['createdAt'];
      DateTime? created;
      if (createdRaw is String && createdRaw.trim().isNotEmpty) {
        created = DateTime.tryParse(createdRaw.trim())?.toUtc();
      }
      final schemaVersion = schema is int
          ? schema
          : (schema is num ? schema.toInt() : int.tryParse('$schema'));
      if ((path == null || path.isEmpty) &&
          (name == null || name.isEmpty) &&
          created == null &&
          (app == null || app.isEmpty) &&
          schemaVersion == null) {
        return const BackupZipManifest.unknown();
      }
      return BackupZipManifest(
        originalDatabasePath: (path == null || path.isEmpty) ? null : path,
        databaseFileName: (name == null || name.isEmpty) ? null : name,
        createdAt: created,
        appVersion: (app == null || app.isEmpty) ? null : app,
        schemaVersion: schemaVersion,
      );
    } catch (_) {
      return const BackupZipManifest.unknown();
    }
  }

  static BackupZipManifest readFromArchive(Archive archive) {
    try {
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final name = f.name.replaceAll('\\', '/');
        if (name == zipEntryName || name.endsWith('/$zipEntryName')) {
          final content = f.content;
          if (content.isEmpty) {
            return const BackupZipManifest.unknown();
          }
          return parseJson(utf8.decode(content));
        }
      }
    } catch (_) {
      return const BackupZipManifest.unknown();
    }
    return const BackupZipManifest.unknown();
  }

  static Future<BackupZipManifest> readFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return const BackupZipManifest.unknown();
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return const BackupZipManifest.unknown();
      return parseJson(utf8.decode(bytes));
    } catch (_) {
      return const BackupZipManifest.unknown();
    }
  }

  /// Δημιουργεί [ArchiveFile] για προσθήκη στο zip.
  static ArchiveFile toArchiveFile(BackupZipManifest manifest) {
    final bytes = Uint8List.fromList(manifest.toUtf8Bytes());
    return ArchiveFile(zipEntryName, bytes.length, bytes);
  }
}
