import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../config/app_config.dart';
import 'database_file_bundle.dart';
import 'database_file_identity.dart';
import 'database_init_result.dart';
import 'database_integrity_probe.dart';

enum ProbeSeverity { info, warning, error }

class ProbeFinding {
  const ProbeFinding({
    required this.severity,
    required this.code,
    required this.message,
    this.hint,
  });

  final ProbeSeverity severity;
  final String code;
  final String message;
  final String? hint;
}

class DatabaseAccessProbeReport {
  const DatabaseAccessProbeReport({required this.findings, this.fatalResult});

  final List<ProbeFinding> findings;
  final DatabaseInitResult? fatalResult;

  bool get hasFindings => findings.isNotEmpty;
  bool get hasWarnings =>
      findings.any((f) => f.severity == ProbeSeverity.warning);
  bool get hasErrors => findings.any((f) => f.severity == ProbeSeverity.error);

  String get humanReadable {
    if (findings.isEmpty) return '';
    final buffer = StringBuffer('Διαγνωστικά πρόσβασης βάσης:');
    for (final finding in findings) {
      final prefix = switch (finding.severity) {
        ProbeSeverity.info => '[OK]',
        ProbeSeverity.warning => '[WARN]',
        ProbeSeverity.error => '[ERR]',
      };
      buffer.writeln();
      buffer.write('$prefix ${finding.message}');
      final hint = finding.hint?.trim();
      if (hint != null && hint.isNotEmpty) {
        buffer.write(' ($hint)');
      }
    }
    return buffer.toString();
  }
}

class DatabaseAccessProbe {
  const DatabaseAccessProbe();

  static const Duration _kProbeTotalTimeout = Duration(milliseconds: 1000);
  static const Duration _kShortStepTimeout = Duration(milliseconds: 250);
  static const Duration _kSweepTimeout = Duration(milliseconds: 400);
  static const String _kSqliteHeader = 'SQLite format 3\x00';
  static const int _kLargeWalThresholdBytes = 4 * 1024 * 1024;
  static const int _kLowDiskSpaceThresholdBytes = 50 * 1024 * 1024;

  /// Ηλικία πάνω από την οποία ένα δοκιμαστικό αρχείο θεωρείται ξεχασμένο.
  ///
  /// Το κανονικό probe ζει χιλιοστά του δευτερολέπτου. Το περιθώριο υπάρχει
  /// ώστε να μην πειραχθεί ΠΟΤΕ το ζωντανό probe μιας δεύτερης εκκίνησης που
  /// τρέχει την ίδια στιγμή στον ίδιο φάκελο.
  static const Duration _kStaleProbeAge = Duration(minutes: 5);

  /// Μόνο ό,τι φτιάχνει το [_checkParentWritable]: `.__probe_<ms>_<τυχαίο>.tmp`.
  ///
  /// Το μοτίβο είναι σκόπιμα αυστηρό — στον φάκελο της βάσης ζουν αντίγραφα,
  /// `-wal`/`-shm` και αρχεία του χρήστη, και τίποτα από αυτά δεν επιτρέπεται
  /// να ακουμπήσει ο καθαρισμός.
  static final RegExp _kProbeLeftoverPattern = RegExp(
    r'^\.__probe_\d+_\d+\.tmp$',
  );

  Future<DatabaseAccessProbeReport> probe(String dbPath) async {
    final report = await _runProbe(dbPath).timeout(
      _kProbeTotalTimeout,
      onTimeout: () => const DatabaseAccessProbeReport(
        findings: <ProbeFinding>[
          ProbeFinding(
            severity: ProbeSeverity.warning,
            code: 'probe_timeout',
            message: 'Ο διαγνωστικός έλεγχος πρόσβασης έληξε σε timeout.',
            hint:
                'Η εκκίνηση θα συνεχιστεί κανονικά και θα συλλεχθούν στοιχεία από τα επόμενα βήματα.',
          ),
        ],
      ),
    );

    // Έξω από το χρονικό όριο των διαγνωστικών πρόσβασης: ο έλεγχος
    // περιεχομένου απαντά σε άλλο ερώτημα και έχει δικό του όριο.
    final extra = <ProbeFinding>[];
    if (report.fatalResult == null) {
      final integrity = await _checkContentIntegrity(dbPath);
      if (integrity != null) extra.add(integrity);
    }

    // Έξω από το χρονικό όριο των διαγνωστικών: ο καθαρισμός δεν είναι
    // διάγνωση και δεν επιτρέπεται να τρώει από τον χρόνο της.
    extra.addAll(await sweepStaleWriteProbes(dbPath));
    if (extra.isEmpty) return report;
    return DatabaseAccessProbeReport(
      findings: <ProbeFinding>[...report.findings, ...extra],
      fatalResult: report.fatalResult,
    );
  }

  /// Σβήνει ξεχασμένα δοκιμαστικά αρχεία εγγραφής από τον φάκελο της βάσης.
  ///
  /// Το probe του [_checkParentWritable] σβήνεται μόνο του· όταν όμως η
  /// εγγραφή αργήσει πάνω από το όριο (π.χ. antivirus που κρατά το αρχείο),
  /// η διαγραφή αποτυγχάνει και το υπόλειμμα μένει για πάντα. Εδώ μαζεύεται
  /// στην επόμενη εκκίνηση.
  ///
  /// Δεν εμποδίζει ποτέ την εκκίνηση: κάθε αποτυχία καταπίνεται και
  /// ξαναδοκιμάζεται την επόμενη φορά. Επιστρέφει ευρήματα **μόνο** όταν όντως
  /// έσβησε κάτι — βήμα που δηλώνει ότι δεν έκανε τίποτα είναι θόρυβος.
  Future<List<ProbeFinding>> sweepStaleWriteProbes(String dbPath) async {
    try {
      final parent = File(dbPath).parent;
      if (!await parent.exists().timeout(_kSweepTimeout)) {
        return const <ProbeFinding>[];
      }

      final now = DateTime.now();
      var removed = 0;
      var failed = 0;

      final entries = await parent
          .list(followLinks: false)
          .where((entity) => entity is File)
          .toList()
          .timeout(_kSweepTimeout);

      for (final entity in entries) {
        final name = entity.uri.pathSegments.last;
        if (!_kProbeLeftoverPattern.hasMatch(name)) continue;
        final file = File(entity.path);
        try {
          final stat = await file.stat();
          if (now.difference(stat.modified) < _kStaleProbeAge) continue;
          await file.delete();
          removed++;
        } catch (_) {
          // Ακόμη κρατημένο: το αφήνουμε για την επόμενη εκκίνηση.
          failed++;
        }
      }

      if (removed == 0 && failed == 0) return const <ProbeFinding>[];
      return <ProbeFinding>[
        ProbeFinding(
          severity: ProbeSeverity.info,
          code: 'stale_write_probes_swept',
          message: removed == 1
              ? 'Καθαρίστηκε 1 ξεχασμένο δοκιμαστικό αρχείο εγγραφής.'
              : 'Καθαρίστηκαν $removed ξεχασμένα δοκιμαστικά αρχεία εγγραφής.',
          hint: failed == 0
              ? null
              : '$failed δεν σβήστηκαν (πιθανόν κρατούνται) — θα ξαναδοκιμαστούν.',
        ),
      ];
    } catch (_) {
      return const <ProbeFinding>[];
    }
  }

  Future<DatabaseAccessProbeReport> _runProbe(String dbPath) async {
    final findings = <ProbeFinding>[];
    DatabaseInitResult? fatalResult;

    final dbFile = File(dbPath);
    if (!dbFile.existsSync()) {
      fatalResult = DatabaseInitResult.fileNotFound(dbPath);
      findings.add(
        const ProbeFinding(
          severity: ProbeSeverity.error,
          code: 'db_missing',
          message: 'Το αρχείο βάσης δεν υπάρχει στη δηλωμένη διαδρομή.',
        ),
      );
      return DatabaseAccessProbeReport(
        findings: findings,
        fatalResult: fatalResult,
      );
    }

    FileStat dbStat;
    try {
      dbStat = dbFile.statSync();
      findings.add(
        ProbeFinding(
          severity: ProbeSeverity.info,
          code: 'db_exists',
          message: 'Το αρχείο βάσης υπάρχει (${_formatBytes(dbStat.size)}).',
        ),
      );
      if (dbStat.size == 0) {
        fatalResult = DatabaseInitResult.corruptedOrInvalid(
          dbPath,
          'Το αρχείο βάσης είναι κενό (0 bytes).',
        );
        findings.add(
          const ProbeFinding(
            severity: ProbeSeverity.error,
            code: 'db_empty_file',
            message: 'Το αρχείο βάσης είναι κενό (0 bytes).',
          ),
        );
      }
    } catch (e) {
      findings.add(
        ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'db_stat_failed',
          message: 'Αποτυχία ανάγνωσης metadata αρχείου.',
          hint: '$e',
        ),
      );
    }

    if (fatalResult == null) {
      final headerFinding = await _checkSqliteHeader(dbFile, dbPath);
      if (headerFinding != null) {
        findings.add(headerFinding.$1);
        fatalResult ??= headerFinding.$2;
      }
    }

    if (fatalResult == null) {
      final structural = await _checkStructuralConsistency(dbPath);
      if (structural != null) findings.add(structural);
    }

    final readProbe = await _checkReadProbe(dbFile, dbPath);
    if (readProbe != null) {
      findings.add(readProbe.$1);
      fatalResult ??= readProbe.$2;
    }

    final writeProbeFinding = await _checkExclusiveWriteProbe(dbFile);
    if (writeProbeFinding != null) {
      findings.add(writeProbeFinding);
    }

    final parentWritableProbe = await _checkParentWritable(dbFile, dbPath);
    if (parentWritableProbe != null) {
      findings.add(parentWritableProbe.$1);
      fatalResult ??= parentWritableProbe.$2;
    }

    findings.addAll(_checkSidecars(dbPath));
    findings.addAll(await _checkWindowsAttributes(dbPath));
    findings.addAll(await _checkDuplicateInstances());
    findings.addAll(await _checkLowDiskSpace(dbPath));

    if (AppConfig.isUncDatabasePath(dbPath)) {
      final uncProbe = await _checkUncReachability(dbPath);
      if (uncProbe != null) {
        findings.add(uncProbe.$1);
        fatalResult ??= uncProbe.$2;
      }
    }

    return DatabaseAccessProbeReport(
      findings: findings,
      fatalResult: fatalResult,
    );
  }

  Future<(ProbeFinding, DatabaseInitResult?)?> _checkSqliteHeader(
    File dbFile,
    String dbPath,
  ) async {
    try {
      final bytes = await dbFile.readAsBytes().timeout(_kShortStepTimeout);
      if (bytes.length < _kSqliteHeader.length) {
        return (
          const ProbeFinding(
            severity: ProbeSeverity.error,
            code: 'sqlite_header_short',
            message:
                'Το αρχείο βάσης είναι μικρότερο από την ελάχιστη κεφαλίδα SQLite.',
          ),
          DatabaseInitResult.corruptedOrInvalid(
            dbPath,
            'Το αρχείο βάσης δεν περιέχει πλήρη κεφαλίδα SQLite.',
          ),
        );
      }

      final header = String.fromCharCodes(bytes.take(_kSqliteHeader.length));
      if (header != _kSqliteHeader) {
        return (
          const ProbeFinding(
            severity: ProbeSeverity.error,
            code: 'sqlite_header_mismatch',
            message: 'Το αρχείο δεν έχει έγκυρη κεφαλίδα SQLite.',
            hint: 'Αναμενόταν "SQLite format 3".',
          ),
          DatabaseInitResult.corruptedOrInvalid(
            dbPath,
            'Το αρχείο δεν μοιάζει με έγκυρη βάση SQLite (ασυμφωνία κεφαλίδας).',
          ),
        );
      }

      return (
        const ProbeFinding(
          severity: ProbeSeverity.info,
          code: 'sqlite_header_ok',
          message: 'Έγκυρη κεφαλίδα SQLite.',
        ),
        null,
      );
    } on TimeoutException {
      return (
        const ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'sqlite_header_probe_timeout',
          message: 'Καθυστέρηση στην ανάγνωση κεφαλίδας SQLite.',
        ),
        null,
      );
    } on FileSystemException catch (e) {
      final lower = e.toString().toLowerCase();
      final denied =
          lower.contains('access is denied') ||
          lower.contains('permission denied') ||
          (e.osError?.errorCode == 5);
      return (
        ProbeFinding(
          severity: ProbeSeverity.error,
          code: 'sqlite_header_read_failed',
          message: 'Αποτυχία ανάγνωσης κεφαλίδας SQLite.',
          hint: '$e',
        ),
        denied
            ? DatabaseInitResult.accessDenied(
                dbPath,
                'Δεν επιτρέπεται η ανάγνωση του αρχείου βάσης.',
              )
            : null,
      );
    } catch (e) {
      return (
        ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'sqlite_header_probe_failed',
          message: 'Ο έλεγχος κεφαλίδας SQLite απέτυχε.',
          hint: '$e',
        ),
        null,
      );
    }
  }

  /// Χωρά το αρχείο τις σελίδες που δηλώνει η κεφαλίδα του;
  ///
  /// Κοστίζει 100 bytes και πιάνει το αντίγραφο που κόπηκε στη μέση — αρχείο
  /// που «υπάρχει, διαβάζεται, γράφεται» και παρ' όλα αυτά δεν ανοίγει.
  ///
  /// **Αναφέρει, δεν μπλοκάρει.** Την απόφαση αν η βάση ανοίγει τη δίνει το
  /// άνοιγμα· ένα διαγνωστικό δεν κλειδώνει κανέναν έξω από τη βάση του.
  Future<ProbeFinding?> _checkStructuralConsistency(String dbPath) async {
    final identity = await readDatabaseFileIdentity(dbPath);
    final verdict = inspectDatabaseFileStructure(identity);
    if (verdict == DatabaseStructuralVerdict.unknown || identity == null) {
      return null;
    }
    if (verdict == DatabaseStructuralVerdict.ok) {
      return ProbeFinding(
        severity: ProbeSeverity.info,
        code: 'structure_consistent',
        message:
            'Το αρχείο χωρά τις ${identity.pageCount} σελίδες που δηλώνει.',
      );
    }
    final declared = identity.pageCount * identity.pageSize;
    return ProbeFinding(
      severity: ProbeSeverity.error,
      code: 'db_file_truncated',
      message:
          'Το αρχείο είναι μικρότερο από όσο δηλώνει η κεφαλίδα του: '
          '${_formatBytes(identity.fileSize)} αντί για '
          '${_formatBytes(declared)}.',
      hint: 'Τυπικό σημάδι αντιγραφής που δεν ολοκληρώθηκε.',
    );
  }

  /// Ρωτά το SQLite αν το **περιεχόμενο** στέκει — το ερώτημα που κανένας
  /// άλλος έλεγχος εδώ δεν αγγίζει.
  ///
  /// Οι υπόλοιποι έλεγχοι απαντούν «υπάρχει; διαβάζεται; γράφεται;». Ένα
  /// αρχείο μπορεί να περνά και τα τρία και να είναι άχρηστο· τότε ο χρήστης
  /// βλέπει σειρά από «[OK]» κάτω από ένα «φαίνεται κατεστραμμένο».
  ///
  /// **Αναφέρει, δεν μπλοκάρει** — και το ωμό κείμενο του SQLite περνά
  /// αυτούσιο στο `hint`, χωρίς μετάφραση.
  Future<ProbeFinding?> _checkContentIntegrity(String dbPath) async {
    final outcome = await runDatabaseIntegrityProbe(dbPath);
    final raw = outcome.rawMessage?.trim();
    switch (outcome.status) {
      case DatabaseIntegrityStatus.ok:
        return const ProbeFinding(
          severity: ProbeSeverity.info,
          code: 'integrity_ok',
          message: 'Ο έλεγχος ακεραιότητας περιεχομένου δεν βρήκε πρόβλημα.',
        );
      case DatabaseIntegrityStatus.inconclusive:
        if (raw == null || raw.isEmpty) return null;
        return ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'integrity_inconclusive',
          message: 'Ο έλεγχος ακεραιότητας δεν κατέληξε.',
          hint: raw,
        );
      case DatabaseIntegrityStatus.corrupt:
        return ProbeFinding(
          severity: ProbeSeverity.error,
          code: 'integrity_failed',
          message: 'Ο έλεγχος ακεραιότητας βρήκε χαλασμένο περιεχόμενο.',
          hint: (raw == null || raw.isEmpty) ? null : raw,
        );
    }
  }

  Future<(ProbeFinding, DatabaseInitResult?)?> _checkReadProbe(
    File dbFile,
    String dbPath,
  ) async {
    RandomAccessFile? raf;
    try {
      raf = await dbFile.open(mode: FileMode.read).timeout(_kShortStepTimeout);
      return (
        const ProbeFinding(
          severity: ProbeSeverity.info,
          code: 'read_probe_ok',
          message: 'Η ανάγνωση του αρχείου βάσης είναι επιτρεπτή.',
        ),
        null,
      );
    } on FileSystemException catch (e) {
      final lower = e.toString().toLowerCase();
      final denied =
          lower.contains('access is denied') ||
          lower.contains('permission denied') ||
          (e.osError?.errorCode == 5);
      return (
        ProbeFinding(
          severity: ProbeSeverity.error,
          code: 'read_access_denied',
          message: 'Άρνηση πρόσβασης κατά το read probe.',
          hint: '$e',
        ),
        denied ? DatabaseInitResult.accessDenied(dbPath) : null,
      );
    } on TimeoutException {
      return (
        const ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'read_probe_timeout',
          message: 'Το read probe καθυστέρησε περισσότερο από το όριο.',
        ),
        null,
      );
    } catch (e) {
      return (
        ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'read_probe_failed',
          message: 'Το read probe απέτυχε με άγνωστο σφάλμα.',
          hint: '$e',
        ),
        null,
      );
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  Future<ProbeFinding?> _checkExclusiveWriteProbe(File dbFile) async {
    RandomAccessFile? raf;
    try {
      raf = await dbFile
          .open(mode: FileMode.append)
          .timeout(_kShortStepTimeout);
      return const ProbeFinding(
        severity: ProbeSeverity.info,
        code: 'write_probe_ok',
        message: 'Το write probe ολοκληρώθηκε επιτυχώς.',
      );
    } on FileSystemException catch (e) {
      final lower = e.toString().toLowerCase();
      final sharedViolation =
          lower.contains('sharing violation') ||
          lower.contains('used by another process') ||
          (e.osError?.errorCode == 32) ||
          (e.osError?.errorCode == 33);
      return ProbeFinding(
        severity: ProbeSeverity.warning,
        code: sharedViolation
            ? 'file_is_held_by_another_process'
            : 'write_probe_failed',
        message: sharedViolation
            ? 'Το αρχείο πιθανόν κρατιέται από άλλη διεργασία.'
            : 'Αποτυχία στο write probe.',
        hint: '$e',
      );
    } on TimeoutException {
      return const ProbeFinding(
        severity: ProbeSeverity.warning,
        code: 'write_probe_timeout',
        message: 'Το write probe καθυστέρησε περισσότερο από το όριο.',
      );
    } catch (e) {
      return ProbeFinding(
        severity: ProbeSeverity.warning,
        code: 'write_probe_unknown_error',
        message: 'Το write probe απέτυχε με άγνωστο σφάλμα.',
        hint: '$e',
      );
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  Future<(ProbeFinding, DatabaseInitResult?)?> _checkParentWritable(
    File dbFile,
    String dbPath,
  ) async {
    final parent = dbFile.parent;
    if (!parent.existsSync()) {
      return (
        const ProbeFinding(
          severity: ProbeSeverity.error,
          code: 'parent_missing',
          message: 'Ο γονικός φάκελος της βάσης δεν υπάρχει.',
        ),
        DatabaseInitResult.fileNotFound(dbPath),
      );
    }

    final probeName =
        '.__probe_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}.tmp';
    final probeFile = File('${parent.path}${Platform.pathSeparator}$probeName');

    try {
      await probeFile.writeAsString('probe').timeout(_kShortStepTimeout);
      await probeFile.delete().timeout(_kShortStepTimeout);
      return (
        const ProbeFinding(
          severity: ProbeSeverity.info,
          code: 'parent_writable',
          message: 'Ο γονικός φάκελος επιτρέπει εγγραφή.',
        ),
        null,
      );
    } on FileSystemException catch (e) {
      return (
        ProbeFinding(
          severity: ProbeSeverity.error,
          code: 'parent_folder_not_writable',
          message: 'Ο γονικός φάκελος της βάσης δεν επιτρέπει εγγραφή.',
          hint: '$e',
        ),
        DatabaseInitResult.accessDenied(
          dbPath,
          'Ο φάκελος της βάσης δεν είναι εγγράψιμος από την εφαρμογή.',
        ),
      );
    } on TimeoutException {
      return (
        const ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'parent_writable_probe_timeout',
          message: 'Ο έλεγχος εγγραφής στον γονικό φάκελο έληξε σε timeout.',
        ),
        null,
      );
    } finally {
      try {
        if (await probeFile.exists()) {
          await probeFile.delete();
        }
      } catch (_) {}
    }
  }

  List<ProbeFinding> _checkSidecars(String dbPath) {
    final findings = <ProbeFinding>[];
    final now = DateTime.now();

    for (final suffix in kDatabaseSidecarSuffixes) {
      final f = File('$dbPath$suffix');
      if (!f.existsSync()) continue;
      try {
        final stat = f.statSync();
        final age = now.difference(stat.modified);
        findings.add(
          ProbeFinding(
            severity: ProbeSeverity.info,
            code: 'sidecar_present_$suffix',
            message:
                'Βρέθηκε sidecar ${f.path.split(Platform.pathSeparator).last} (${_formatBytes(stat.size)}).',
          ),
        );

        if (suffix == '-journal' && stat.size > 0) {
          findings.add(
            const ProbeFinding(
              severity: ProbeSeverity.warning,
              code: 'hot_journal_present',
              message:
                  'Υπάρχει ημερολόγιο αναίρεσης: προηγούμενη εγγραφή δεν '
                  'ολοκληρώθηκε.',
              hint:
                  'Το άνοιγμα θα την αναιρέσει πρώτα — αναμένεται μικρή '
                  'καθυστέρηση.',
            ),
          );
        }

        if (suffix == '-wal' && stat.size > _kLargeWalThresholdBytes) {
          findings.add(
            ProbeFinding(
              severity: ProbeSeverity.warning,
              code: 'wal_recovery_expected_slow',
              message:
                  'Το αρχείο WAL είναι μεγάλο (${_formatBytes(stat.size)}), αναμένεται αργό άνοιγμα.',
            ),
          );
        }

        if (age.inHours >= 24) {
          findings.add(
            ProbeFinding(
              severity: ProbeSeverity.info,
              code: 'stale_sidecars_detected',
              message:
                  'Εντοπίστηκε παλιό sidecar (${age.inHours} ώρες). Θα επιχειρηθεί καθαρισμός.',
            ),
          );
        }
      } catch (e) {
        findings.add(
          ProbeFinding(
            severity: ProbeSeverity.warning,
            code: 'sidecar_stat_failed',
            message: 'Αποτυχία ανάγνωσης metadata sidecar $suffix.',
            hint: '$e',
          ),
        );
      }
    }

    return findings;
  }

  Future<List<ProbeFinding>> _checkWindowsAttributes(String dbPath) async {
    if (!Platform.isWindows) return const <ProbeFinding>[];
    try {
      final result = await Process.run('attrib', <String>[
        dbPath,
      ], runInShell: true).timeout(_kShortStepTimeout);
      if (result.exitCode != 0) return const <ProbeFinding>[];
      final output = (result.stdout as String).trim().toUpperCase();
      final findings = <ProbeFinding>[];
      if (output.contains(' R ')) {
        findings.add(
          const ProbeFinding(
            severity: ProbeSeverity.warning,
            code: 'read_only_attribute',
            message: 'Το αρχείο έχει attribute Read-only.',
          ),
        );
      }
      if (output.contains(' H ') || output.contains(' S ')) {
        findings.add(
          const ProbeFinding(
            severity: ProbeSeverity.info,
            code: 'hidden_or_system_attribute',
            message: 'Το αρχείο έχει Hidden/System attribute.',
          ),
        );
      }
      return findings;
    } catch (_) {
      return const <ProbeFinding>[];
    }
  }

  Future<List<ProbeFinding>> _checkDuplicateInstances() async {
    if (!Platform.isWindows) return const <ProbeFinding>[];
    try {
      final result = await Process.run('tasklist', <String>[
        '/fo',
        'csv',
        '/nh',
        '/fi',
        'IMAGENAME eq call_logger.exe',
      ], runInShell: true).timeout(_kShortStepTimeout);
      if (result.exitCode != 0) return const <ProbeFinding>[];
      final out = (result.stdout as String).trim();
      if (out.isEmpty || out.toLowerCase().contains('no tasks are running')) {
        return const <ProbeFinding>[];
      }

      final lines = out
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length <= 1) return const <ProbeFinding>[];

      return <ProbeFinding>[
        ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'multiple_app_instances',
          message:
              'Εντοπίστηκαν ${lines.length} ενεργά αντίγραφα της εφαρμογής call_logger.exe.',
          hint: 'Κλείστε τα επιπλέον αντίγραφα και ξαναδοκιμάστε.',
        ),
      ];
    } catch (_) {
      return const <ProbeFinding>[];
    }
  }

  Future<List<ProbeFinding>> _checkLowDiskSpace(String dbPath) async {
    if (!Platform.isWindows) return const <ProbeFinding>[];
    if (AppConfig.isUncDatabasePath(dbPath)) return const <ProbeFinding>[];
    final drive = _extractWindowsDrive(dbPath);
    if (drive == null) return const <ProbeFinding>[];

    try {
      final result = await Process.run('fsutil', <String>[
        'volume',
        'diskfree',
        drive,
      ], runInShell: true).timeout(_kShortStepTimeout);
      if (result.exitCode != 0) return const <ProbeFinding>[];
      final out = (result.stdout as String);
      final allMatches = RegExp(r'(\d+)').allMatches(out).toList();
      if (allMatches.isEmpty) return const <ProbeFinding>[];
      final freeBytes = int.tryParse(allMatches.first.group(1)!);
      if (freeBytes == null) return const <ProbeFinding>[];
      if (freeBytes >= _kLowDiskSpaceThresholdBytes) {
        return const <ProbeFinding>[];
      }
      return <ProbeFinding>[
        ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'low_disk_space',
          message:
              'Χαμηλός ελεύθερος χώρος στον δίσκο ($drive): ${_formatBytes(freeBytes)}.',
        ),
      ];
    } catch (_) {
      return const <ProbeFinding>[];
    }
  }

  Future<(ProbeFinding, DatabaseInitResult?)?> _checkUncReachability(
    String dbPath,
  ) async {
    final root = _extractUncRoot(dbPath);
    if (root == null) return null;
    try {
      final ok = await Directory(
        root,
      ).exists().timeout(const Duration(milliseconds: 400));
      if (ok) {
        return (
          ProbeFinding(
            severity: ProbeSeverity.info,
            code: 'unc_reachable',
            message: 'Το UNC share είναι προσβάσιμο: $root',
          ),
          null,
        );
      }
      return (
        ProbeFinding(
          severity: ProbeSeverity.error,
          code: 'unc_share_unreachable',
          message: 'Το UNC share δεν είναι προσβάσιμο: $root',
        ),
        const DatabaseInitResult(
          status: DatabaseStatus.accessDenied,
          message: 'Δεν είναι προσβάσιμο το UNC share της βάσης δεδομένων.',
        ),
      );
    } on TimeoutException {
      return (
        ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'unc_reachability_timeout',
          message: 'Ο έλεγχος προσβασιμότητας UNC έληξε σε timeout.',
        ),
        null,
      );
    } catch (e) {
      return (
        ProbeFinding(
          severity: ProbeSeverity.warning,
          code: 'unc_reachability_failed',
          message: 'Αποτυχία ελέγχου UNC share.',
          hint: '$e',
        ),
        null,
      );
    }
  }

  String? _extractWindowsDrive(String path) {
    final trimmed = path.trim();
    if (trimmed.length < 2) return null;
    if (trimmed[1] != ':') return null;
    return trimmed.substring(0, 2);
  }

  String? _extractUncRoot(String path) {
    final trimmed = path.trim().replaceAll('/', r'\');
    if (!trimmed.startsWith(r'\\')) return null;
    final parts = trimmed.split(r'\').where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) return null;
    return '\\\\${parts[0]}\\${parts[1]}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}
