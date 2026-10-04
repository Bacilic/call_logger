import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Best-effort διαγνωστικός εντοπισμός διεργασιών που κρατούν SQLite αρχεία.
///
/// **Καμία διαδρομή δεν ενώνεται μέσα σε εντολή, και τίποτα δεν περνά από
/// κέλυφος.** Οι διαδρομές δίνονται στα εξωτερικά προγράμματα ως ορίσματα ή ως
/// μεταβλητή περιβάλλοντος για σταθερό σενάριο — όποιους χαρακτήρες κι αν
/// έχουν (`&`, `'`, `$`), διαβάζονται αυτούσιοι και δεν εκτελούνται ποτέ.
class LockDiagnosticService {
  const LockDiagnosticService();

  /// Μέσα από εδώ φτάνουν οι διαδρομές στο σενάριο PowerShell, μία ανά γραμμή.
  static const String targetsEnvironmentVariable = 'CALL_LOGGER_LOCK_TARGETS';

  /// Σταθερό σενάριο: δεν περιέχει ποτέ δεδομένα, μόνο τα διαβάζει.
  static const String _powerShellScript = r'''
$targets = @($env:CALL_LOGGER_LOCK_TARGETS -split "`n" |
  ForEach-Object { $_.Trim().ToLowerInvariant() } |
  Where-Object { $_ -ne '' })
$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -ne $null }
$matched = foreach ($p in $procs) {
  $cmd = $p.CommandLine.ToLowerInvariant()
  foreach ($t in $targets) {
    if ($cmd.Contains($t)) {
      [PSCustomObject]@{
        Process = $p.Name
        PID = $p.ProcessId
        Path = $p.ExecutablePath
      }
      break
    }
  }
}
$matched | Sort-Object PID -Unique | Format-Table -AutoSize | Out-String -Width 4096
''';

  /// Τα ορίσματα του PowerShell. Το σενάριο πάει κωδικοποιημένο, ώστε ούτε τα
  /// εισαγωγικά ούτε οι αλλαγές γραμμής του να χρειάζονται διαφυγή.
  static List<String> powerShellArguments() => <String>[
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-EncodedCommand',
    base64.encode(_utf16LittleEndian(_powerShellScript)),
  ];

  /// Το περιβάλλον που δίνει τις διαδρομές στο σενάριο — ως δεδομένα.
  static Map<String, String> powerShellEnvironment(List<String> targets) =>
      <String, String>{targetsEnvironmentVariable: targets.join('\n')};

  static List<int> _utf16LittleEndian(String text) {
    final bytes = <int>[];
    for (final unit in text.codeUnits) {
      bytes
        ..add(unit & 0xFF)
        ..add(unit >> 8);
    }
    return bytes;
  }

  static const List<String> _knownHandleLocations = <String>[
    r'C:\Sysinternals\handle.exe',
    r'C:\SysinternalsSuite\handle.exe',
    r'C:\Program Files\Sysinternals\handle.exe',
    r'C:\Program Files\SysinternalsSuite\handle.exe',
  ];

  Future<String> detectLockingProcess(String dbPath) async {
    try {
      final targets = _candidateTargets(dbPath);
      final handlePath = await _resolveHandleExecutable();

      if (handlePath != null) {
        final handleResult = await _runHandleDiagnostics(handlePath, targets);
        if (handleResult != null && handleResult.trim().isNotEmpty) {
          return 'Lock diagnostics (handle.exe):\n$handleResult';
        }
      }

      final psResult = await _runPowerShellFallback(targets);
      if (psResult != null && psResult.trim().isNotEmpty) {
        return 'Lock diagnostics (PowerShell fallback):\n$psResult';
      }

      return 'Δεν εντοπίστηκε διεργασία που κρατά τη βάση (best-effort).';
    } catch (e, st) {
      // Ποτέ crash: επιστροφή διαγνωστικού string μόνο.
      return 'Αποτυχία lock diagnostics: $e\n$st';
    }
  }

  List<String> _candidateTargets(String dbPath) {
    final normalized = p.normalize(dbPath.trim());
    final targets = <String>[normalized, '$normalized-wal', '$normalized-shm'];
    return targets.toSet().toList();
  }

  Future<String?> _resolveHandleExecutable() async {
    try {
      final whereResult = await Process.run('where.exe', <String>[
        'handle.exe',
      ]);
      if (whereResult.exitCode == 0) {
        final lines = (whereResult.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) {
          return lines.first;
        }
      }
    } catch (_) {}

    for (final candidate in _knownHandleLocations) {
      try {
        if (await File(candidate).exists()) {
          return candidate;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _runHandleDiagnostics(
    String handlePath,
    List<String> targets,
  ) async {
    final output = <String>[];
    for (final target in targets) {
      try {
        final r = await Process.run(handlePath, <String>['-nobanner', target]);
        final stdoutText = (r.stdout as String).trim();
        if (stdoutText.isNotEmpty &&
            !stdoutText.toLowerCase().contains('no matching handles')) {
          output.add('Target: $target');
          output.add(stdoutText);
        }
      } catch (_) {}
    }
    if (output.isEmpty) return null;
    return output.join('\n');
  }

  Future<String?> _runPowerShellFallback(List<String> targets) async {
    try {
      final r = await Process.run(
        'powershell.exe',
        powerShellArguments(),
        environment: powerShellEnvironment(targets),
      );
      if (r.exitCode != 0) return null;
      final text = (r.stdout as String).trim();
      if (text.isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }
}
