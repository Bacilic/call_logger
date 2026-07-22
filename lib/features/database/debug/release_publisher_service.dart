import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'installer_script_builder.dart';

/// Είδος bump έκδοσης (το build αυξάνεται πάντα κατά 1).
enum VersionBumpKind { patch, minor }

enum ReleasePublishStatus {
  success,
  emptyUnreleasedWarning,
  failure,
}

class ReleasePublishResult {
  const ReleasePublishResult({
    required this.status,
    this.failedStep,
    this.message,
    this.newVersion,
    this.newBuild,
  });

  final ReleasePublishStatus status;
  final String? failedStep;
  final String? message;
  final String? newVersion;
  final int? newBuild;

  bool get isSuccess => status == ReleasePublishStatus.success;
}

/// Προεπισκόπηση δημοσίευσης χωρίς παρενέργειες.
class ReleasePublishPreview {
  const ReleasePublishPreview({
    required this.currentVersion,
    required this.currentBuild,
    required this.nextVersion,
    required this.nextBuild,
    required this.unreleasedEntryCount,
    required this.hasUnreleasedEntries,
    required this.bumpKind,
  });

  final String currentVersion;
  final int currentBuild;
  final String nextVersion;
  final int nextBuild;
  final int unreleasedEntryCount;
  final bool hasUnreleasedEntries;
  final VersionBumpKind bumpKind;
}

typedef ReleaseProcessRunner = Future<int> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  void Function(String line)? onOutput,
});

/// Ανάγνωση zip από δίσκο για επαλήθευση SHA (injectable στα τεστ).
typedef ZipVerificationReader = Future<Uint8List> Function(String zipPath);

class _ProjectFileSnapshot {
  const _ProjectFileSnapshot({
    required this.changelogJson,
    required this.changelogMd,
    required this.pubspec,
  });

  final Uint8List changelogJson;
  final Uint8List changelogMd;
  final Uint8List pubspec;
}

/// Τελετή δημοσίευσης έκδοσης (debug) — χωρίς UI και χωρίς SQL.
class ReleasePublisherService {
  ReleasePublisherService({
    required this.projectRoot,
    required this.buildReleaseDirectory,
    required this.updateFolderPath,
    required this.processRunner,
    required this.clock,
    this.onProgress,
    ZipVerificationReader? verificationReader,
  }) : verificationReader = verificationReader ?? _defaultVerificationReader;

  final String projectRoot;
  final String buildReleaseDirectory;
  final String updateFolderPath;
  final ReleaseProcessRunner processRunner;
  final DateTime Function() clock;
  final void Function(String message)? onProgress;
  final ZipVerificationReader verificationReader;

  static const _categoryKeys = ['added', 'improvements', 'changed', 'fixed'];

  static const _mdSectionTitles = {
    'added': 'Προστέθηκε',
    'improvements': 'Μικροβελτιώσεις',
    'changed': 'Άλλαξε',
    'fixed': 'Διορθώθηκε',
  };

  static Future<Uint8List> _defaultVerificationReader(String zipPath) =>
      File(zipPath).readAsBytes();

  static const List<String> forbiddenZipPrefixes = [
    'Data Base/',
    'images/',
    'maps_images/',
    'dictionaries/',
    'logs/',
  ];

  /// Δημόσια για τεστ: απορρίπτει zip με φακέλους δεδομένων χρήστη.
  static void assertZipHasNoUserData(Archive archive) {
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      for (final prefix in forbiddenZipPrefixes) {
        if (name == prefix.substring(0, prefix.length - 1) ||
            name.startsWith(prefix) ||
            name.contains('/$prefix')) {
          throw StateError(
            'Το πακέτο περιέχει απαγορευμένη εγγραφή δεδομένων χρήστη: $name',
          );
        }
      }
    }
  }

  /// Χωρίς εγγραφές: τρέχουσα/επόμενη έκδοση και πλήθος Unreleased.
  /// Ο τύπος αύξησης προκύπτει αυτόματα από το περιεχόμενο του Unreleased.
  Future<ReleasePublishPreview> preparePreview() async {
    final current = await _readPubspecVersion();
    final unreleased = await _readUnreleasedMap();
    final count = _countEntriesIn(unreleased);
    final kind = _bumpKindFromUnreleased(unreleased);
    final bumped = _bumpVersion(current.version, current.build, kind);
    return ReleasePublishPreview(
      currentVersion: current.version,
      currentBuild: current.build,
      nextVersion: bumped.version,
      nextBuild: bumped.build,
      unreleasedEntryCount: count,
      hasUnreleasedEntries: count > 0,
      bumpKind: kind,
    );
  }

  /// Γράφει ΜΟΝΟ το `install_call_logger.bat` στη ρίζα του φακέλου ενημερώσεων.
  Future<ReleasePublishResult> writeInstallerOnly() async {
    try {
      _progress('Εγγραφή install_call_logger.bat…');
      final folder = updateFolderPath.trim();
      if (folder.isEmpty) {
        return const ReleasePublishResult(
          status: ReleasePublishStatus.failure,
          failedStep: 'εγγραφή εγκαταστάτη',
          message: 'Δεν έχει οριστεί φάκελος ενημερώσεων.',
        );
      }
      final dir = Directory(folder);
      if (!await dir.exists()) {
        return const ReleasePublishResult(
          status: ReleasePublishStatus.failure,
          failedStep: 'εγγραφή εγκαταστάτη',
          message:
              'Ο φάκελος ενημερώσεων δεν υπάρχει ή δεν είναι προσβάσιμος.',
        );
      }
      final batPath = p.join(folder, 'install_call_logger.bat');
      await File(batPath).writeAsBytes(
        InstallerScriptBuilder.buildBytes(),
        flush: true,
      );
      return const ReleasePublishResult(
        status: ReleasePublishStatus.success,
        message: 'Ο εγκαταστάτης install_call_logger.bat ανανεώθηκε.',
      );
    } catch (e) {
      return ReleasePublishResult(
        status: ReleasePublishStatus.failure,
        failedStep: 'εγγραφή εγκαταστάτη',
        message: e.toString(),
      );
    }
  }

  Future<ReleasePublishResult> publish() async {
    _ProjectFileSnapshot? snapshot;
    try {
      _progress('Έλεγχος Unreleased…');
      final unreleased = await _readUnreleasedMap();
      if (_countEntriesIn(unreleased) == 0) {
        return const ReleasePublishResult(
          status: ReleasePublishStatus.emptyUnreleasedWarning,
          message:
              'Η ενότητα Unreleased στο changelog είναι κενή. '
              'Προσθέστε καταχωρήσεις πριν τη δημοσίευση.',
        );
      }

      snapshot = await _snapshotProjectFiles();

      final bumpKind = _bumpKindFromUnreleased(unreleased);
      final current = await _readPubspecVersion();
      final bumped = _bumpVersion(current.version, current.build, bumpKind);
      final releasedDate = _formatDate(clock());

      _progress('Σφράγιση changelog…');
      await _sealChangelogJson(
        bumpKind: bumpKind,
        version: bumped.version,
        date: releasedDate,
      );
      await _sealChangelogMarkdown(
        bumpKind: bumpKind,
        version: bumped.version,
        date: releasedDate,
      );

      _progress('Bump έκδοσης στο pubspec.yaml…');
      await _writePubspecVersion(bumped.version, bumped.build);

      _progress('flutter build windows --release…');
      final buildCode = await processRunner(
        'flutter',
        const ['build', 'windows', '--release'],
        workingDirectory: projectRoot,
        onOutput: (line) => _progress(line),
      );
      if (buildCode != 0) {
        await _restoreProjectFiles(snapshot);
        return ReleasePublishResult(
          status: ReleasePublishStatus.failure,
          failedStep: 'flutter build',
          message: 'Το flutter build απέτυχε με κωδικό $buildCode.',
        );
      }

      _progress('Πακετάρισμα allowlist…');
      final packaged = await _collectAllowlistedFiles();
      if (packaged.isEmpty) {
        await _restoreProjectFiles(snapshot);
        return const ReleasePublishResult(
          status: ReleasePublishStatus.failure,
          failedStep: 'πακετάρισμα',
          message: 'Δεν βρέθηκαν προϊόντα μεταγλώττισης στον φάκελο Release.',
        );
      }

      final zipName = 'call_logger_${bumped.version}.zip';
      final archive = Archive();
      for (final entry in packaged.entries) {
        final bytes = entry.value;
        archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
      }
      final updateSourceJson = utf8.encode(
        jsonEncode({'updateFolderPath': updateFolderPath}),
      );
      archive.addFile(
        ArchiveFile(
          'update_source.json',
          updateSourceJson.length,
          updateSourceJson,
        ),
      );

      try {
        assertZipHasNoUserData(archive);
      } catch (e) {
        await _restoreProjectFiles(snapshot);
        return ReleasePublishResult(
          status: ReleasePublishStatus.failure,
          failedStep: 'δικλείδα ασφαλείας zip',
          message: e.toString(),
        );
      }

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final sha = sha256.convert(zipBytes).toString();

      _progress('Εγγραφή zip στον φάκελο ενημερώσεων…');
      final currentDir = Directory(p.join(updateFolderPath, 'current'));
      final appDir = Directory(p.join(currentDir.path, 'app'));
      final releasesDir = Directory(
        p.join(updateFolderPath, 'releases', bumped.version),
      );
      await currentDir.create(recursive: true);
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
      await appDir.create(recursive: true);
      await releasesDir.create(recursive: true);

      final zipPath = p.join(currentDir.path, zipName);
      await File(zipPath).writeAsBytes(zipBytes, flush: true);
      await File(p.join(releasesDir.path, zipName))
          .writeAsBytes(zipBytes, flush: true);

      _progress('Εγγραφή current/app…');
      for (final entry in packaged.entries) {
        final dest = File(p.join(appDir.path, entry.key));
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(entry.value, flush: true);
      }

      _progress('Παραγωγή install_call_logger.bat…');
      final batPath = p.join(updateFolderPath, 'install_call_logger.bat');
      await File(batPath).writeAsBytes(
        InstallerScriptBuilder.buildBytes(),
        flush: true,
      );

      _progress('Επαλήθευση ακεραιότητας zip…');
      final onDisk = await verificationReader(zipPath);
      final onDiskSha = sha256.convert(onDisk).toString();
      if (onDiskSha != sha) {
        await _restoreProjectFiles(snapshot);
        return const ReleasePublishResult(
          status: ReleasePublishStatus.failure,
          failedStep: 'επαλήθευση ακεραιότητας',
          message:
              'Το SHA-256 του zip στον δίσκο δεν ταιριάζει με τον υπολογισμό '
              'στη μνήμη. Το version.json δεν γράφτηκε.',
        );
      }

      _progress('Εγγραφή version.json…');
      final manifest = {
        'version': bumped.version,
        'build': bumped.build,
        'released': releasedDate,
        'zipFile': zipName,
        'sha256': sha,
      };
      final manifestJson =
          const JsonEncoder.withIndent('  ').convert(manifest);
      final versionTmp = File(p.join(currentDir.path, 'version.json.tmp'));
      final versionFinal = File(p.join(currentDir.path, 'version.json'));
      await versionTmp.writeAsString(manifestJson, flush: true);
      if (await versionFinal.exists()) {
        await versionFinal.delete();
      }
      await versionTmp.rename(versionFinal.path);

      _progress('Ολοκληρώθηκε η δημοσίευση ${bumped.version}+${bumped.build}.');
      return ReleasePublishResult(
        status: ReleasePublishStatus.success,
        message: 'Δημοσιεύτηκε η έκδοση ${bumped.version}+${bumped.build}.',
        newVersion: bumped.version,
        newBuild: bumped.build,
      );
    } catch (e) {
      if (snapshot != null) {
        try {
          await _restoreProjectFiles(snapshot);
        } catch (_) {
          // Το αρχικό σφάλμα έχει προτεραιότητα.
        }
      }
      return ReleasePublishResult(
        status: ReleasePublishStatus.failure,
        failedStep: 'άγνωστο',
        message: e.toString(),
      );
    }
  }

  void _progress(String message) => onProgress?.call(message);

  File get _changelogJsonFile =>
      File(p.join(projectRoot, 'assets', 'changelog.json'));
  File get _changelogMdFile => File(p.join(projectRoot, 'CHANGELOG.md'));
  File get _pubspecFile => File(p.join(projectRoot, 'pubspec.yaml'));

  Future<_ProjectFileSnapshot> _snapshotProjectFiles() async {
    return _ProjectFileSnapshot(
      changelogJson: await _changelogJsonFile.readAsBytes(),
      changelogMd: await _changelogMdFile.readAsBytes(),
      pubspec: await _pubspecFile.readAsBytes(),
    );
  }

  Future<void> _restoreProjectFiles(_ProjectFileSnapshot snapshot) async {
    await _changelogJsonFile.writeAsBytes(snapshot.changelogJson, flush: true);
    await _changelogMdFile.writeAsBytes(snapshot.changelogMd, flush: true);
    await _pubspecFile.writeAsBytes(snapshot.pubspec, flush: true);
  }

  Future<Map<String, dynamic>> _readUnreleasedMap() async {
    final list = await _readChangelogJson();
    final unreleased = list.cast<Map>().firstWhere(
          (e) => (e['version'] as String?) == 'Unreleased',
          orElse: () => <String, dynamic>{},
        );
    return Map<String, dynamic>.from(unreleased);
  }

  static int _countEntriesIn(Map<String, dynamic> unreleased) {
    if (unreleased.isEmpty) return 0;
    var count = 0;
    for (final key in _categoryKeys) {
      final raw = unreleased[key];
      if (raw is! List) continue;
      count += raw.where((e) => e.toString().trim().isNotEmpty).length;
    }
    return count;
  }

  static VersionBumpKind _bumpKindFromUnreleased(
    Map<String, dynamic> unreleased,
  ) {
    final added = unreleased['added'];
    if (added is List &&
        added.any((e) => e.toString().trim().isNotEmpty)) {
      return VersionBumpKind.minor;
    }
    return VersionBumpKind.patch;
  }

  Future<List<dynamic>> _readChangelogJson() async {
    final raw = jsonDecode(await _changelogJsonFile.readAsString());
    if (raw is! List) {
      throw StateError('Το changelog.json δεν είναι πίνακας.');
    }
    return raw;
  }

  Map<String, dynamic> _emptyUnreleased() => {
        'version': 'Unreleased',
        'date': '',
        'added': <String>[],
        'improvements': <String>[],
        'changed': <String>[],
        'fixed': <String>[],
      };

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) => e.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  Future<void> _sealChangelogJson({
    required VersionBumpKind bumpKind,
    required String version,
    required String date,
  }) async {
    final list = await _readChangelogJson();
    final unreleasedIndex = list.indexWhere(
      (e) => e is Map && e['version'] == 'Unreleased',
    );
    if (unreleasedIndex < 0) {
      throw StateError('Δεν βρέθηκε ενότητα Unreleased στο changelog.json.');
    }
    final unreleased =
        Map<String, dynamic>.from(list[unreleasedIndex] as Map);

    if (bumpKind == VersionBumpKind.minor) {
      final sealed = Map<String, dynamic>.from(unreleased);
      sealed['version'] = version;
      sealed['date'] = date;
      for (final key in _categoryKeys) {
        sealed[key] = _stringList(sealed[key]);
      }
      list[unreleasedIndex] = sealed;
      list.insert(0, _emptyUnreleased());
    } else {
      final topIndex = list.indexWhere(
        (e) => e is Map && e['version'] != 'Unreleased',
      );
      if (topIndex < 0) {
        throw StateError(
          'Δεν βρέθηκε δημοσιευμένη κάρτα για συγχώνευση patch.',
        );
      }
      final top = Map<String, dynamic>.from(list[topIndex] as Map);
      top['version'] = version;
      top['date'] = date;
      for (final key in _categoryKeys) {
        final existing = _stringList(top[key]);
        final incoming = _stringList(unreleased[key]);
        top[key] = [...existing, ...incoming];
      }
      list[topIndex] = top;
      list[unreleasedIndex] = _emptyUnreleased();
    }

    await _changelogJsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(list),
      flush: true,
    );
  }

  Future<void> _sealChangelogMarkdown({
    required VersionBumpKind bumpKind,
    required String version,
    required String date,
  }) async {
    final content = await _changelogMdFile.readAsString();
    const marker = '## [Unreleased]';
    final idx = content.indexOf(marker);
    if (idx < 0) {
      throw StateError('Δεν βρέθηκε ## [Unreleased] στο CHANGELOG.md.');
    }

    if (bumpKind == VersionBumpKind.minor) {
      final sealedHeader = '## [$version] - $date';
      final updated = content.replaceFirst(marker, sealedHeader);
      final insertAt = updated.indexOf(sealedHeader);
      final withNewUnreleased = updated.replaceRange(
        insertAt,
        insertAt,
        '## [Unreleased]\n\n',
      );
      await _changelogMdFile.writeAsString(withNewUnreleased, flush: true);
      return;
    }

    final nextHeader = RegExp(r'^## \[', multiLine: true);
    final afterUnreleased = idx + marker.length;
    final nextMatch = nextHeader.firstMatch(content.substring(afterUnreleased));
    if (nextMatch == null) {
      throw StateError(
        'Δεν βρέθηκε δημοσιευμένη ενότητα στο CHANGELOG.md για patch.',
      );
    }
    final topStart = afterUnreleased + nextMatch.start;
    final unreleasedBody = content.substring(afterUnreleased, topStart).trim();
    final afterTopHeaderLine = content.indexOf('\n', topStart);
    final topHeaderEnd =
        afterTopHeaderLine < 0 ? content.length : afterTopHeaderLine + 1;
    final restMatch =
        nextHeader.firstMatch(content.substring(topHeaderEnd));
    final topEnd =
        restMatch == null ? content.length : topHeaderEnd + restMatch.start;
    final topBody = content.substring(topHeaderEnd, topEnd).trimRight();

    final incoming = _parseMdSections(unreleasedBody);
    final mergedBody = _mergeMdSections(topBody, incoming);
    final prefix = content.substring(0, idx);
    final suffix = content.substring(topEnd);
    final rebuilt = StringBuffer()
      ..write(prefix)
      ..writeln('## [Unreleased]')
      ..writeln()
      ..writeln('## [$version] - $date')
      ..writeln()
      ..write(mergedBody.trimRight())
      ..writeln()
      ..writeln()
      ..write(suffix.trimLeft());

    await _changelogMdFile.writeAsString(rebuilt.toString(), flush: true);
  }

  static Map<String, List<String>> _parseMdSections(String body) {
    final result = {
      for (final key in _categoryKeys) key: <String>[],
    };
    final titleToKey = {
      for (final e in _mdSectionTitles.entries) e.value: e.key,
    };
    String? currentKey;
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trimRight();
      final header = RegExp(r'^###\s+(.+)$').firstMatch(line.trim());
      if (header != null) {
        currentKey = titleToKey[header.group(1)!.trim()];
        continue;
      }
      if (currentKey == null) continue;
      final bullet = RegExp(r'^-\s+(.+)$').firstMatch(line.trim());
      if (bullet != null) {
        final text = bullet.group(1)!.trim();
        if (text.isNotEmpty) result[currentKey]!.add(text);
      }
    }
    return result;
  }

  static String _mergeMdSections(
    String existingBody,
    Map<String, List<String>> incoming,
  ) {
    final existing = _parseMdSections(existingBody);
    final buffer = StringBuffer();
    var first = true;
    for (final key in _categoryKeys) {
      final items = [...existing[key]!, ...incoming[key]!];
      if (items.isEmpty) continue;
      if (!first) buffer.writeln();
      first = false;
      buffer.writeln('### ${_mdSectionTitles[key]}');
      buffer.writeln();
      for (final item in items) {
        buffer.writeln('- $item');
      }
    }
    return buffer.toString();
  }

  Future<({String version, int build})> _readPubspecVersion() async {
    final text = await _pubspecFile.readAsString();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(text);
    if (match == null) {
      throw StateError('Δεν βρέθηκε έγκυρο version στο pubspec.yaml.');
    }
    return (version: match.group(1)!, build: int.parse(match.group(2)!));
  }

  Future<void> _writePubspecVersion(String version, int build) async {
    final text = await _pubspecFile.readAsString();
    final updated = text.replaceFirstMapped(
      RegExp(r'^version:\s*.+$', multiLine: true),
      (_) => 'version: $version+$build',
    );
    await _pubspecFile.writeAsString(updated, flush: true);
  }

  /// Pure αύξηση έκδοσης X.Y.Z (χωρίς build). Κακοδιαμορφωμένη είσοδος → αυτούσια.
  static String nextVersion(String current, VersionBumpKind kind) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(current.trim());
    if (match == null) return current;
    var major = int.parse(match.group(1)!);
    var minor = int.parse(match.group(2)!);
    var patch = int.parse(match.group(3)!);
    switch (kind) {
      case VersionBumpKind.patch:
        patch += 1;
      case VersionBumpKind.minor:
        minor += 1;
        patch = 0;
    }
    return '$major.$minor.$patch';
  }

  static ({String version, int build}) _bumpVersion(
    String version,
    int build,
    VersionBumpKind kind,
  ) {
    return (version: nextVersion(version, kind), build: build + 1);
  }

  static String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Allowlist: call_logger.exe, *.dll, data/**, native_assets.json — όχι .pdb / user data.
  Future<Map<String, Uint8List>> _collectAllowlistedFiles() async {
    final root = Directory(buildReleaseDirectory);
    if (!await root.exists()) {
      return {};
    }
    final result = <String, Uint8List>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      if (!_isAllowlistedRelativePath(relative)) continue;
      result[relative] = await entity.readAsBytes();
    }
    return result;
  }

  static bool _isAllowlistedRelativePath(String relative) {
    final name = relative.replaceAll('\\', '/');
    if (name.contains('..')) return false;
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdb')) return false;
    if (name == 'call_logger.exe') return true;
    if (name == 'native_assets.json') return true;
    if (lower.endsWith('.dll') && !name.contains('/')) return true;
    if (name == 'data' || name.startsWith('data/')) return true;
    return false;
  }
}
