import 'dart:io';

import 'package:path/path.dart' as p;

/// Best-effort διαγνωστικός εντοπισμός διεργασιών που κρατούν SQLite αρχεία.
class LockDiagnosticService {
  const LockDiagnosticService();

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
      final whereResult = await Process.run('where', <String>[
        'handle.exe',
      ], runInShell: true);
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
        final r = await Process.run(handlePath, <String>[
          '-nobanner',
          target,
        ], runInShell: true);
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
    final escaped = targets
        .map(
          (t) => t.replaceAll(r'\', r'\\').replaceAll("'", "''").toLowerCase(),
        )
        .toList();

    final script =
        '''
\$targets = @(${escaped.map((e) => "'$e'").join(',')})
\$procs = Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -ne \$null }
\$matched = foreach (\$p in \$procs) {
  \$cmd = \$p.CommandLine.ToLowerInvariant()
  foreach (\$t in \$targets) {
    if (\$cmd.Contains(\$t)) {
      [PSCustomObject]@{
        Process = \$p.Name
        PID = \$p.ProcessId
        Path = \$p.ExecutablePath
      }
      break
    }
  }
}
\$matched | Sort-Object PID -Unique | Format-Table -AutoSize | Out-String -Width 4096
''';

    try {
      final r = await Process.run('powershell', <String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ], runInShell: true);
      if (r.exitCode != 0) return null;
      final text = (r.stdout as String).trim();
      if (text.isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }
}
