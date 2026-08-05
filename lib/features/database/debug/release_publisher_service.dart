import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'installer_script_builder.dart';

/// Είδος bump έκδοσης (το build αυξάνεται πάντα κατά 1).
enum VersionBumpKind { patch, minor }

enum ReleasePublishStatus { success, emptyUnreleasedWarning, failure }

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

typedef ReleaseProcessRunner =
    Future<int> Function(
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
    required this.pubspec,
  });

  final Uint8List changelogJson;
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

  /// Πόσες εκδόσεις κρατά το `releases/` μετά από κάθε δημοσίευση.
  static const int retainedReleaseCount = 5;

  /// Μόνο δικά μας πακέτα επιτρέπεται να διαγραφούν από τη συντήρηση:
  /// `call_logger_X.Y.Z(build).zip` και το παλιό `call_logger_X.Y.Z.zip`
  /// (χωρίς κτίσιμο), ώστε να καθαρίζονται και όσα δημοσιεύτηκαν πριν την
  /// αλλαγή ονοματοδοσίας.
  static final RegExp _publishedZipPattern = RegExp(
    r'^call_logger_\d+\.\d+\.\d+(\(\d+\))?\.zip$',
    caseSensitive: false,
  );

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
          message: 'Ο φάκελος ενημερώσεων δεν υπάρχει ή δεν είναι προσβάσιμος.',
        );
      }
      final batPath = p.join(folder, 'install_call_logger.bat');
      await File(
        batPath,
      ).writeAsBytes(InstallerScriptBuilder.buildBytes(), flush: true);
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
      // Μοναδική πηγή αλήθειας το assets/changelog.json — δεν συντηρείται
      // πλέον CHANGELOG.md (απόφαση 03/08/2026, η παράλληλη συντήρηση
      // δημιουργούσε μόνιμη ασυμφωνία).
      await _sealChangelogJson(
        bumpKind: bumpKind,
        version: bumped.version,
        date: releasedDate,
      );

      _progress('Bump έκδοσης στο pubspec.yaml…');
      await _writePubspecVersion(bumped.version, bumped.build);

      return await _buildPackageAndPublish(
        version: bumped.version,
        build: bumped.build,
        releasedDate: releasedDate,
        snapshot: snapshot,
        completionVerb: 'Δημοσιεύτηκε',
      );
    } catch (e) {
      return _failureAfterRestore(e, snapshot);
    }
  }

  /// Ξαναχτίζει και ξαναδημοσιεύει την τρέχουσα έκδοση **χωρίς νέο αριθμό
  /// έκδοσης και χωρίς να αγγίξει το ιστορικό αλλαγών**.
  ///
  /// Δύο πραγματικές ανάγκες:
  /// 1. αλλαγές που δεν δικαιολογούν καταχώρηση ιστορικού (εσωτερικές
  ///    διορθώσεις, εργαλεία αποσφαλμάτωσης) αλλά πρέπει να φτάσουν στους
  ///    χρήστες·
  /// 2. επιδιόρθωση κατεστραμμένου/άδειου φακέλου ενημερώσεων.
  ///
  /// Η ετικέτα `X.Y.Z` μένει ΙΔΙΑ — αυξάνεται μόνο ο αριθμός κτισίματος, ώστε
  /// οι εγκατεστημένες εφαρμογές να δουν την ενημέρωση (η σύγκριση «υπάρχει
  /// νεότερη έκδοση;» γίνεται με το build, όχι με την ετικέτα).
  Future<ReleasePublishResult> rebuildCurrentVersion() async {
    _ProjectFileSnapshot? snapshot;
    try {
      snapshot = await _snapshotProjectFiles();
      final current = await _readPubspecVersion();
      final nextBuild = current.build + 1;

      _progress(
        'Αύξηση αριθμού κτισίματος σε $nextBuild '
        '(η έκδοση ${current.version} και το ιστορικό μένουν ως έχουν)…',
      );
      await _writePubspecVersion(current.version, nextBuild);

      return await _buildPackageAndPublish(
        version: current.version,
        build: nextBuild,
        releasedDate: _formatDate(clock()),
        snapshot: snapshot,
        completionVerb: 'Αναδημοσιεύτηκε',
      );
    } catch (e) {
      return _failureAfterRestore(e, snapshot);
    }
  }

  /// Κοινό φινάλε των [publish] και [rebuildCurrentVersion]: μεταγλώττιση,
  /// πακετάρισμα, zip, εγγραφή στον φάκελο ενημερώσεων, εγκαταστάτης,
  /// επαλήθευση ακεραιότητας, `version.json` και συντήρηση.
  ///
  /// Κάθε αποτυχία επαναφέρει τα αρχεία του έργου από το [snapshot]: ό,τι
  /// άλλαξε ο καλών (changelog, έκδοση) γυρίζει πίσω byte-προς-byte.
  Future<ReleasePublishResult> _buildPackageAndPublish({
    required String version,
    required int build,
    required String releasedDate,
    required _ProjectFileSnapshot snapshot,
    required String completionVerb,
  }) async {
    try {
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

      // Το κτίσιμο μπαίνει στο όνομα: αλλιώς μια αναδημοσίευση της ίδιας
      // έκδοσης θα αντικαθιστούσε σιωπηλά το προηγούμενο πακέτο — και στο
      // `current/` και στο αρχείο `releases/`, χάνοντας το τι ακριβώς είχε
      // σταλεί. Το όνομα δεν το μαντεύει κανείς: όλη η ροή ενημέρωσης το
      // διαβάζει από το `zipFile` του manifest.
      final zipName = 'call_logger_$version($build).zip';
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
        p.join(updateFolderPath, 'releases', version),
      );
      await currentDir.create(recursive: true);
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
      await appDir.create(recursive: true);
      await releasesDir.create(recursive: true);

      final zipPath = p.join(currentDir.path, zipName);
      await File(zipPath).writeAsBytes(zipBytes, flush: true);
      await File(
        p.join(releasesDir.path, zipName),
      ).writeAsBytes(zipBytes, flush: true);

      _progress('Εγγραφή current/app…');
      for (final entry in packaged.entries) {
        final dest = File(p.join(appDir.path, entry.key));
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(entry.value, flush: true);
      }

      _progress('Παραγωγή install_call_logger.bat…');
      final batPath = p.join(updateFolderPath, 'install_call_logger.bat');
      await File(
        batPath,
      ).writeAsBytes(InstallerScriptBuilder.buildBytes(), flush: true);

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
        'version': version,
        'build': build,
        'released': releasedDate,
        'zipFile': zipName,
        'sha256': sha,
      };
      final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);
      final versionTmp = File(p.join(currentDir.path, 'version.json.tmp'));
      final versionFinal = File(p.join(currentDir.path, 'version.json'));
      await versionTmp.writeAsString(manifestJson, flush: true);
      if (await versionFinal.exists()) {
        await versionFinal.delete();
      }
      await versionTmp.rename(versionFinal.path);

      // Συντήρηση ΜΟΝΟ μετά από πλήρως επιτυχή δημοσίευση: μια αποτυχία
      // παραπάνω δεν πρέπει ποτέ να έχει σβήσει τίποτα.
      await _cleanUpdateFolder(currentDir: currentDir, keepZipName: zipName);

      _progress('Ολοκληρώθηκε: $version+$build.');
      return ReleasePublishResult(
        status: ReleasePublishStatus.success,
        message: '$completionVerb η έκδοση $version+$build.',
        newVersion: version,
        newBuild: build,
      );
    } catch (e) {
      return _failureAfterRestore(e, snapshot);
    }
  }

  /// Επαναφέρει τα αρχεία του έργου (αν υπάρχει [snapshot]) και επιστρέφει
  /// αποτυχία. Αποτυχία της ίδιας της επαναφοράς δεν σκεπάζει το αρχικό σφάλμα.
  Future<ReleasePublishResult> _failureAfterRestore(
    Object error,
    _ProjectFileSnapshot? snapshot,
  ) async {
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
      message: error.toString(),
    );
  }

  void _progress(String message) => onProgress?.call(message);

  /// Συντήρηση φακέλου ενημερώσεων μετά από ΕΠΙΤΥΧΗ δημοσίευση.
  ///
  /// Στο `current/` μένει μόνο το zip της νέας έκδοσης· στο `releases/` οι
  /// [retainedReleaseCount] νεότερες εκδόσεις. Διαγράφεται ΜΟΝΟ ό,τι ταιριάζει
  /// στα αναμενόμενα μοτίβα ονομάτων (`call_logger_X.Y.Z.zip`, φάκελοι `X.Y.Z`)
  /// — οτιδήποτε ξένο βρεθεί στους φακέλους δεν αγγίζεται. Κάθε διαγραφή
  /// αναφέρεται στην πρόοδο· αποτυχία διαγραφής δεν αποτυγχάνει τη δημοσίευση
  /// (θα ξαναδοκιμαστεί αυτόματα στην επόμενη).
  Future<void> _cleanUpdateFolder({
    required Directory currentDir,
    required String keepZipName,
  }) async {
    _progress('Συντήρηση φακέλου ενημερώσεων…');
    try {
      await for (final entity in currentDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name == keepZipName) continue;
        if (!_publishedZipPattern.hasMatch(name)) continue;
        try {
          await entity.delete();
          _progress('Διαγράφηκε παλιό zip: current/$name');
        } catch (e) {
          _progress('Αποτυχία διαγραφής current/$name: $e');
        }
      }
    } catch (e) {
      _progress('Η συντήρηση του current/ διακόπηκε: $e');
    }

    try {
      final releasesRoot = Directory(p.join(updateFolderPath, 'releases'));
      if (!await releasesRoot.exists()) return;
      final versioned = <(Directory, (int, int, int))>[];
      await for (final entity in releasesRoot.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final version = _parseVersionFolderName(p.basename(entity.path));
        if (version == null) continue;
        versioned.add((entity, version));
      }
      versioned.sort((a, b) => _compareVersionTuples(b.$2, a.$2));
      for (final (dir, _) in versioned.skip(retainedReleaseCount)) {
        final name = p.basename(dir.path);
        try {
          await dir.delete(recursive: true);
          _progress('Διαγράφηκε παλιά έκδοση: releases/$name');
        } catch (e) {
          _progress('Αποτυχία διαγραφής releases/$name: $e');
        }
      }
    } catch (e) {
      _progress('Η συντήρηση του releases/ διακόπηκε: $e');
    }
  }

  static (int, int, int)? _parseVersionFolderName(String name) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(name.trim());
    if (match == null) return null;
    return (
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  static int _compareVersionTuples((int, int, int) a, (int, int, int) b) {
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
    return a.$3.compareTo(b.$3);
  }

  File get _changelogJsonFile =>
      File(p.join(projectRoot, 'assets', 'changelog.json'));
  File get _pubspecFile => File(p.join(projectRoot, 'pubspec.yaml'));

  Future<_ProjectFileSnapshot> _snapshotProjectFiles() async {
    return _ProjectFileSnapshot(
      changelogJson: await _changelogJsonFile.readAsBytes(),
      pubspec: await _pubspecFile.readAsBytes(),
    );
  }

  Future<void> _restoreProjectFiles(_ProjectFileSnapshot snapshot) async {
    await _changelogJsonFile.writeAsBytes(snapshot.changelogJson, flush: true);
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
    if (added is List && added.any((e) => e.toString().trim().isNotEmpty)) {
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
    final unreleased = Map<String, dynamic>.from(list[unreleasedIndex] as Map);

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
