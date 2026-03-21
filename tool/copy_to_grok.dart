// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

/// Script που αντιγράφει συγκεκριμένα αρχεία στο φάκελο Grok.
/// Δέχεται ονόματα αρχεία ή paths (χωρισμένα με κόμμα).
/// Path: χρήση απευθείας. Όνομα αρχείου: αναδρομική αναζήτηση σε lib/ και root.
/// Αν κάποιο αρχείο δεν βρεθεί: fuzzy προτάσεις + διαδραστική επιλογή (stdin).
///
/// Παράδειγμα: dart run tool/copy_to_grok.dart main.dart,lib/features/tasks/models/task.dart
void main(List<String> arguments) {
  try {
    final projectRoot = Directory.current;
    final grokDir = Directory('${projectRoot.path}${Platform.pathSeparator}Grok');
    final sep = Platform.pathSeparator;

    _prepareGrokDirectory(grokDir);

    final items = _parseItems(arguments);
    if (items.isEmpty) {
      print(
        'Δεν δόθηκαν αρχεία. Χρήση: dart run tool/copy_to_grok.dart file1.dart,lib/path/to/file2.dart',
      );
      exit(1);
    }

    final libDir = Directory('${projectRoot.path}$sep''lib');
    final rootAbs = p.normalize(projectRoot.absolute.path);

    // Όλα τα σχετικά paths (μοναδικά) για fuzzy matching — μία συλλογή ανά run.
    final allFilenames = _collectAllFilenames(projectRoot, libDir);

    final outcomes = <_CopyOutcome>[];
    for (final item in items) {
      outcomes.add(_resolveItem(item, projectRoot, libDir, rootAbs, sep));
    }

    final autoOk = outcomes.whereType<_CopyOk>().toList();
    final missing = outcomes.whereType<_CopyMissing>().map((m) => m.item).toList();

    final interactive = missing.isNotEmpty
        ? _handleMissingInteractive(
            missing,
            allFilenames,
            libDir,
            projectRoot,
            rootAbs,
          )
        : (copies: <_CopyOk>[], skippedQueries: 0);

    var copiedCount = 0;

    for (final ok in autoOk) {
      _copyFileToGrok(ok, grokDir, sep);
      copiedCount++;
    }

    for (final ok in interactive.copies) {
      _copyFileToGrok(ok, grokDir, sep);
      copiedCount++;
    }

    final skippedCount = interactive.skippedQueries;

    _printFinalSummary(
      copiedCount,
      skippedCount,
      hadInteractiveMissing: missing.isNotEmpty,
    );
  } on IOException catch (e) {
    print('Σφάλμα I/O: $e');
    exit(1);
  } catch (e, st) {
    print('Σφάλμα: $e');
    print(st);
    exit(1);
  }
}

// —————————————————————————————————————————————————————————————————————
// Fuzzy matching (Levenshtein + heuristics)
// —————————————————————————————————————————————————————————————————————

int _levenshteinDistance(String s1, String s2) {
  if (s1 == s2) return 0;
  if (s1.isEmpty) return s2.length;
  if (s2.isEmpty) return s1.length;
  final m = s1.length;
  final n = s2.length;
  var prev = List<int>.generate(n + 1, (j) => j);
  var curr = List<int>.filled(n + 1, 0);
  for (var i = 0; i < m; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < n; j++) {
      final cost = s1.codeUnitAt(i) == s2.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = math.min(
        math.min(curr[j] + 1, prev[j + 1] + 1),
        prev[j] + cost,
      );
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[n];
}

/// Βασικό score 0..1 από Levenshtein, με bonuses (cap στο 1.0).
/// [candidate] συγκρίνεται κυρίως ως basename· [candidateFullPath] για λέξεις-κλειδιά στο path.
double _similarityScore(
  String query,
  String candidate, {
  String? candidateFullPath,
}) {
  final q = query.toLowerCase().trim();
  final c = candidate.toLowerCase().trim();
  if (q.isEmpty && c.isEmpty) return 1.0;
  if (q.isEmpty || c.isEmpty) return 0.0;

  final dist = _levenshteinDistance(q, c);
  final maxLen = math.max(q.length, c.length);
  var score = 1.0 - dist / maxLen;

  final haystack = (candidateFullPath ?? candidate).toLowerCase();
  const keywords = ['model', 'service', 'list', 'screen', 'widget'];
  if (keywords.any((k) => haystack.contains(k))) {
    score += 0.25;
  }

  final qEndsS = q.endsWith('s') && q.length > 1;
  final cEndsS = c.endsWith('s') && c.length > 1;
  if (qEndsS != cEndsS) {
    score += 0.15;
  }

  return score > 1.0 ? 1.0 : score;
}

// —————————————————————————————————————————————————————————————————————
// Αρχεία project & προτάσεις
// —————————————————————————————————————————————————————————————————————

/// Συλλογή σχετικών διαδρομών αρχείων από τη ρίζα [root] (αποκλείονται θόρυβοι όπως Grok, build).
List<String> _collectAllFilenames(Directory root, Directory libDir) {
  final rootPath = p.normalize(root.absolute.path);
  final seen = <String>{};

  const skipDirNames = {
    'Grok',
    '.dart_tool',
    'build',
    '.git',
    '.idea',
    'node_modules',
  };

  void walk(Directory dir) {
    if (!dir.existsSync()) return;
    try {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (skipDirNames.contains(name)) continue;
          walk(entity);
        } else if (entity is File) {
          final rel = p.relative(entity.path, from: rootPath);
          seen.add(rel);
        }
      }
    } on IOException {
      // συνεχίζουμε με ό,τι συλλέχθηκε
    }
  }

  walk(root);
  // Αν το lib είναι εκτός root (ασυνήθιστο), συμπληρώνουμε ξεχωριστά.
  if (libDir.existsSync()) {
    final libNorm = p.normalize(libDir.absolute.path);
    if (!libNorm.startsWith(rootPath)) {
      walk(libDir);
    }
  }

  final list = seen.toList()..sort();
  return list;
}

class _Suggestion {
  _Suggestion(this.file, this.score, this.displayName);

  final File file;
  final double score;
  final String displayName;
}

/// Top προτάσεις για [query] μέσα σε [allFiles] (σχετικές διαδρομές από project root).
List<_Suggestion> _findSuggestions(
  String query,
  List<String> allFiles,
  Directory libDir,
  Directory projectRoot,
) {
  final rootPath = projectRoot.absolute.path;
  final q = query.trim();
  if (q.isEmpty) return [];

  final scored = <_Suggestion>[];

  for (final rel in allFiles) {
    final file = File(p.join(rootPath, rel));
    if (!file.existsSync()) continue;

    final base = p.basename(rel);
    final baseNoExt = p.basenameWithoutExtension(rel);
    final relLower = rel.replaceAll(r'\', '/');

    final s1 = _similarityScore(q, base, candidateFullPath: relLower);
    final s2 = _similarityScore(q, baseNoExt, candidateFullPath: relLower);
    final score = math.max(s1, s2);

    scored.add(_Suggestion(file, score, base));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(5).toList();
}

// —————————————————————————————————————————————————————————————————————
// Interactive missing
// —————————————————————————————————————————————————————————————————————

typedef _InteractivePickResult = ({List<_CopyOk> copies, int skippedQueries});

/// Για κάθε missing: εμφανίζει top-5, διαβάζει stdin.
/// [skippedQueries]: πόσα ζητούμενα δεν αντιστοιχίστηκαν (κενό input, καμία πρόταση, κ.λπ.).
_InteractivePickResult _handleMissingInteractive(
  List<String> missing,
  List<String> allFiles,
  Directory libDir,
  Directory projectRoot,
  String rootAbs,
) {
  final copies = <_CopyOk>[];
  var skippedQueries = 0;

  print('');
  print(
    '— Δεν βρέθηκαν ${missing.length} αρχεία · fuzzy προτάσεις (διαδραστική επιλογή) —',
  );
  print(
    'Εντολές: αριθμοί με κενό ή κόμμα (π.χ. 1 3 ή 1,2), "all" για όλες τις προτάσεις, κενό = παράλειψη.',
  );
  print('');

  for (final item in missing) {
    print('Ζητούμενο: "$item"');
    final suggestions = _findSuggestions(item, allFiles, libDir, projectRoot);

    if (suggestions.isEmpty) {
      print('  (Καμία πρόταση στο project.)');
      skippedQueries++;
      print('');
      continue;
    }

    for (var i = 0; i < suggestions.length; i++) {
      final s = suggestions[i];
      final pct = (s.score * 100).round();
      final relDisp = _displaySourceForLog(s.file.absolute.path, rootAbs);
      print('  ${i + 1}. ${s.displayName}  ($pct%)   $relDisp');
    }

    // Αποφεύγουμε write/flush σε std streams (σε ορισμένα IDE terminals
    // μπορεί να οδηγήσει σε "StreamSink is bound to a stream").
    print('Επιλογή>');
    final line = stdin.readLineSync();
    final input = line?.trim() ?? '';

    if (input.isEmpty) {
      print('  → Παράλειψη.\n');
      skippedQueries++;
      continue;
    }

    final lower = input.toLowerCase();
    final indices = <int>{};

    if (lower == 'skip') {
      print('  → Παράλειψη (skip).\n');
      skippedQueries++;
      continue;
    }
    if (lower == 'all') {
      for (var i = 0; i < suggestions.length; i++) {
        indices.add(i);
      }
    } else {
      for (final part in input.split(RegExp(r'[\s,]+'))) {
        if (part.isEmpty) continue;
        final n = int.tryParse(part);
        if (n == null || n < 1 || n > suggestions.length) {
          print('  ! Αγνόησα μη έγκυρο: "$part"');
          continue;
        }
        indices.add(n - 1);
      }
    }

    if (indices.isEmpty) {
      print('  → Καμία έγκυρη επιλογή — παράλειψη.\n');
      skippedQueries++;
      continue;
    }

    final sortedIdx = indices.toList()..sort();
    for (final idx in sortedIdx) {
      final s = suggestions[idx];
      copies.add(
        _CopyOk(
          source: s.file,
          destFilename: s.displayName,
          srcDisplay: _displaySourceForLog(s.file.absolute.path, rootAbs),
        ),
      );
    }
    print('');
  }

  return (copies: copies, skippedQueries: skippedQueries);
}

// —————————————————————————————————————————————————————————————————————
// Copy outcomes & I/O
// —————————————————————————————————————————————————————————————————————

sealed class _CopyOutcome {}

final class _CopyOk extends _CopyOutcome {
  _CopyOk({required this.source, required this.destFilename, required this.srcDisplay});

  final File source;
  final String destFilename;
  final String srcDisplay;
}

final class _CopyMissing extends _CopyOutcome {
  _CopyMissing(this.item);

  final String item;
}

void _copyFileToGrok(_CopyOk o, Directory grokDir, String sep) {
  final dest = File('${grokDir.path}$sep${o.destFilename}');
  o.source.copySync(dest.path);
  final destDisplay = '\\Grok\\${o.destFilename}';
  print('✓ ${o.destFilename} → $destDisplay');
}

_CopyOutcome _resolveItem(
  String item,
  Directory projectRoot,
  Directory libDir,
  String rootAbs,
  String sep,
) {
  final bool isPath = _isPath(item);
  File? found;
  String destFilename = item;

  if (isPath) {
    final normalized = item.replaceAll('/', sep);
    final candidates = [
      '${projectRoot.path}$sep$normalized',
      '${projectRoot.path}$sep''lib$sep$normalized',
    ];
    for (final pathStr in candidates) {
      final file = File(pathStr);
      if (file.existsSync()) {
        found = file;
        destFilename = file.uri.pathSegments.last;
        break;
      }
    }
  }
  if (found == null) {
    final basename = item.contains('/') || item.contains('\\')
        ? item.replaceAll('\\', '/').split('/').last
        : item;
    found = _findFileRecursively(libDir, basename) ?? _findFileRecursively(projectRoot, basename);
    if (found != null) {
      destFilename = p.basename(found.path);
    }
  }

  if (found != null) {
    final srcDisplay = _displaySourceForLog(found.absolute.path, rootAbs);
    return _CopyOk(source: found, destFilename: destFilename, srcDisplay: srcDisplay);
  }
  return _CopyMissing(item);
}

void _printFinalSummary(
  int copiedCount,
  int skippedCount, {
  required bool hadInteractiveMissing,
}) {
  print('');
  if (hadInteractiveMissing) {
    print('Σύνοψη: Αντιγράφηκαν $copiedCount · Παραλήφθηκαν $skippedCount.');
  } else if (copiedCount == 0) {
    print('Σύνοψη: Δεν αντιγράφηκε κανένα αρχείο.');
  } else {
    print('Σύνοψη: Αντιγράφηκαν $copiedCount αρχείο(α).');
  }
}

/// Μετρά μόνο αρχεία (όχι φακέλους) αναδρομικά.
int _countFilesRecursive(Directory dir) {
  if (!dir.existsSync()) return 0;
  var n = 0;
  try {
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) n++;
    }
  } on IOException {
    return n;
  }
  return n;
}

void _prepareGrokDirectory(Directory grokDir) {
  var fileCount = 0;
  if (grokDir.existsSync()) {
    fileCount = _countFilesRecursive(grokDir);
    grokDir.deleteSync(recursive: true);
  }
  grokDir.createSync(recursive: true);

  if (fileCount == 0) {
    print('[Grok] Καθαρισμός: 0 αρχεία (νέος/άδειος φάκελος).');
  } else if (fileCount == 1) {
    print('[Grok] Διαγράφηκε 1 αρχείο από το φάκελο Grok.');
  } else {
    print('[Grok] Διαγράφηκαν $fileCount αρχεία από το φάκελο Grok.');
  }
}

bool _isPath(String item) => item.contains('/') || item.contains('\\');

List<String> _parseItems(List<String> arguments) {
  if (arguments.isEmpty) return [];
  final singleString = arguments.join(',');
  return singleString
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

File? _findFileRecursively(Directory dir, String filename) {
  if (!dir.existsSync()) return null;
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File) {
        if (entity.path.endsWith(filename) || entity.uri.pathSegments.last == filename) {
          return entity;
        }
      } else if (entity is Directory) {
        final found = _findFileRecursively(entity, filename);
        if (found != null) return found;
      }
    }
  } on IOException {
    return null;
  }
  return null;
}

String _displaySourceForLog(String sourceAbsolute, String projectRootAbsolute) {
  final normSource = p.normalize(sourceAbsolute);
  final normRoot = p.normalize(projectRootAbsolute);
  final libRoot = p.normalize(p.join(normRoot, 'lib'));

  String relativePart;
  if (normSource.startsWith('$libRoot${p.separator}')) {
    relativePart = p.relative(normSource, from: libRoot);
  } else if (normSource.startsWith('$normRoot${p.separator}') || normSource == normRoot) {
    relativePart = p.relative(normSource, from: normRoot);
  } else {
    relativePart = p.basename(normSource);
  }

  final withBackslashes = relativePart.replaceAll(RegExp(r'[/\\]'), r'\');
  return '\\$withBackslashes';
}
