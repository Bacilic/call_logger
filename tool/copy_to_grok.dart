// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

/// Script που αντιγράφει συγκεκριμένα αρχεία στο φάκελο Grok.
/// Δέχεται ονόματα αρχεία ή paths (χωρισμένα με κόμμα)· διπλές εγγραφές στην είσοδο αγνοούνται.
/// Path: χρήση απευθείας. Όνομα αρχείου: όλα τα ταιριάσματα στο project (ίδιο basename).
/// Ένα άτομο → αυτόματη αντιγραφή. Πολλά → διαδραστική επιλογή (και "all" με suffix από path).
/// Αν δεν βρεθεί: fuzzy — έως 7 διακριτά basename (ίδιο όνομα / πολλές διαδρομές = μία πρόταση + suffix).
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

    final allFilenames = _collectAllFilenames(projectRoot, libDir);

    final outcomes = <_CopyOutcome>[];
    for (final item in items) {
      outcomes.add(_resolveItem(item, projectRoot, rootAbs, sep, allFilenames));
    }

    var autoOk = outcomes.whereType<_CopyOk>().toList();
    final ambiguousList = outcomes.whereType<_CopyAmbiguous>().toList();
    final missing = outcomes.whereType<_CopyMissing>().map((m) => m.item).toList();

    autoOk = _dedupeCopyOkBySource(autoOk);

    final copiedSourceAbs = <String>{};

    var automaticCopied = 0;
    print('');
    print('— Αυτόματες αντιγραφές (μοναδικό εύρημα ανά ζητούμενο) —');
    if (autoOk.isEmpty) {
      print('  (Καμία.)');
    }
    for (final ok in autoOk) {
      _copyFileToGrok(ok, grokDir, sep);
      copiedSourceAbs.add(p.normalize(ok.source.absolute.path));
      automaticCopied++;
    }
    print('');

    final ambigResult = ambiguousList.isNotEmpty
        ? _handleAmbiguousInteractive(ambiguousList, rootAbs)
        : (copies: <_CopyOk>[], skippedQueries: 0);

    var ambiguousInteractiveCopied = 0;
    for (final ok in ambigResult.copies) {
      _copyFileToGrok(ok, grokDir, sep);
      copiedSourceAbs.add(p.normalize(ok.source.absolute.path));
      ambiguousInteractiveCopied++;
    }

    final fuzzyResult = missing.isNotEmpty
        ? _handleMissingInteractive(
            missing,
            allFilenames,
            projectRoot,
            rootAbs,
            copiedSourceAbs,
          )
        : (copies: <_CopyOk>[], skippedQueries: 0);

    var fuzzyCopied = 0;
    for (final ok in fuzzyResult.copies) {
      _copyFileToGrok(ok, grokDir, sep);
      copiedSourceAbs.add(p.normalize(ok.source.absolute.path));
      fuzzyCopied++;
    }

    final totalCopied = automaticCopied + ambiguousInteractiveCopied + fuzzyCopied;

    _printFinalSummary(
      totalCopied: totalCopied,
      automaticCopied: automaticCopied,
      ambiguousCopied: ambiguousInteractiveCopied,
      fuzzyCopied: fuzzyCopied,
      skippedAmbiguous: ambigResult.skippedQueries,
      skippedFuzzy: fuzzyResult.skippedQueries,
      hadAmbiguous: ambiguousList.isNotEmpty,
      hadFuzzy: missing.isNotEmpty,
    );

    _openOrFocusGrokInExplorer(grokDir);
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
  if (libDir.existsSync()) {
    final libNorm = p.normalize(libDir.absolute.path);
    if (!libNorm.startsWith(rootPath)) {
      walk(libDir);
    }
  }

  final list = seen.toList()..sort();
  return list;
}

/// Ομάδα fuzzy: ένα basename = μία πρόταση (πολλές διαδρομές = αμφισημία, μία θέση στη λίστα).
class _FuzzyGroup {
  _FuzzyGroup({
    required this.displayName,
    required this.files,
    required this.bestScore,
  });

  final String displayName;
  final List<File> files;
  final double bestScore;

  bool get isAmbiguous => files.length > 1;
}

const int _kFuzzyMaxGroups = 7;
const int _kFuzzyMaxFilesPerAmbiguousGroup = 32;

/// Προτάσεις fuzzy: έως [_kFuzzyMaxGroups] **διακριτά basename**· το ίδιο όνομα σε πολλές θέσεις
/// εμφανίζεται ως μία πρόταση (όχι πολλές από τις 7).
List<_FuzzyGroup> _findFuzzyGroups(
  String query,
  List<String> allFiles,
  Directory projectRoot,
  Set<String> excludeSourceAbsNorm,
) {
  final rootPath = projectRoot.absolute.path;
  final q = query.trim();
  if (q.isEmpty) return [];

  final scored = <({File file, double score, String basename})>[];

  for (final rel in allFiles) {
    final file = File(p.join(rootPath, rel));
    if (!file.existsSync()) continue;
    final norm = p.normalize(file.absolute.path);
    if (excludeSourceAbsNorm.contains(norm)) continue;

    final base = p.basename(rel);
    final baseNoExt = p.basenameWithoutExtension(rel);
    final relLower = rel.replaceAll(r'\', '/');

    final s1 = _similarityScore(q, base, candidateFullPath: relLower);
    final s2 = _similarityScore(q, baseNoExt, candidateFullPath: relLower);
    final score = math.max(s1, s2);

    scored.add((file: file, score: score, basename: base));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));

  final seenBaseLower = <String>{};
  final orderedBasenames = <String>[];
  for (final row in scored) {
    final key = row.basename.toLowerCase();
    if (seenBaseLower.contains(key)) continue;
    seenBaseLower.add(key);
    orderedBasenames.add(row.basename);
    if (orderedBasenames.length >= _kFuzzyMaxGroups) break;
  }

  final scoreByNorm = <String, double>{};
  for (final row in scored) {
    final k = p.normalize(row.file.absolute.path);
    scoreByNorm[k] = math.max(scoreByNorm[k] ?? 0, row.score);
  }

  final groups = <_FuzzyGroup>[];
  for (final displayName in orderedBasenames) {
    final key = displayName.toLowerCase();
    final pathsForBase = <File>[];
    for (final rel in allFiles) {
      if (p.basename(rel).toLowerCase() != key) continue;
      final file = File(p.join(rootPath, rel));
      if (!file.existsSync()) continue;
      final norm = p.normalize(file.absolute.path);
      if (excludeSourceAbsNorm.contains(norm)) continue;
      pathsForBase.add(file);
    }

    if (pathsForBase.isEmpty) continue;

    pathsForBase.sort((a, b) {
      final sa = scoreByNorm[p.normalize(a.absolute.path)] ?? 0;
      final sb = scoreByNorm[p.normalize(b.absolute.path)] ?? 0;
      final c = sb.compareTo(sa);
      if (c != 0) return c;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });

    var list = pathsForBase;
    if (list.length > _kFuzzyMaxFilesPerAmbiguousGroup) {
      list = list.sublist(0, _kFuzzyMaxFilesPerAmbiguousGroup);
    }

    var best = 0.0;
    for (final f in list) {
      final s = scoreByNorm[p.normalize(f.absolute.path)] ?? 0;
      if (s > best) best = s;
    }

    groups.add(_FuzzyGroup(displayName: displayName, files: list, bestScore: best));
  }

  return groups;
}

/// Αν η ομάδα έχει >1 αρχείο (ίδιο basename), χρησιμοποιείται πάντα suffix από path.
void _appendCopiesFromFuzzyGroup(
  _FuzzyGroup group,
  List<_CopyOk> copies,
  Set<String> copiedSourceAbs,
  Set<String> usedDestNames,
  String rootAbs,
) {
  final eligible = group.files
      .where((f) => !copiedSourceAbs.contains(p.normalize(f.absolute.path)))
      .toList();
  if (eligible.isEmpty) {
    return;
  }

  final useSuffix = eligible.length > 1;
  for (final f in eligible) {
    final norm = p.normalize(f.absolute.path);
    if (copiedSourceAbs.contains(norm)) continue;
    var destFilename = useSuffix
        ? _destFilenameWithEncodedPath(f, rootAbs)
        : p.basename(f.path);
    destFilename = _ensureUniqueDestName(destFilename, usedDestNames, f, rootAbs);
    copies.add(
      _CopyOk(
        source: f,
        destFilename: destFilename,
        srcDisplay: _displaySourceForLog(f.absolute.path, rootAbs),
      ),
    );
    copiedSourceAbs.add(norm);
  }
}

// —————————————————————————————————————————————————————————————————————
// Interactive ambiguous (ίδιο basename, πολλές διαδρομές)
// —————————————————————————————————————————————————————————————————————

typedef _InteractivePickResult = ({List<_CopyOk> copies, int skippedQueries});

_InteractivePickResult _handleAmbiguousInteractive(
  List<_CopyAmbiguous> ambiguousList,
  String rootAbs,
) {
  final copies = <_CopyOk>[];
  var skippedQueries = 0;

  print('');
  print(
    '— Ίδιο όνομα αρχείου σε πολλές θέσεις · επιλέξτε αρχείο(α) (μετά τις αυτόματες) —',
  );
  print(
    'Εντολές: αριθμοί με κενό ή κόμμα, "all" = όλα με μοναδικό όνομα (suffix από path), κενό = παράλειψη.',
  );
  print('');

  for (final amb in ambiguousList) {
    final files = List<File>.from(amb.files)
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));

    print('Ζητούμενο: "${amb.item}" · βρέθηκαν ${files.length} αρχεία:');
    for (var i = 0; i < files.length; i++) {
      final relDisp = _displaySourceForLog(files[i].absolute.path, rootAbs);
      print('  ${i + 1}. ${p.basename(files[i].path)}   $relDisp');
    }

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
      for (var i = 0; i < files.length; i++) {
        indices.add(i);
      }
    } else {
      for (final part in input.split(RegExp(r'[\s,]+'))) {
        if (part.isEmpty) continue;
        final n = int.tryParse(part);
        if (n == null || n < 1 || n > files.length) {
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
    final useSuffix = sortedIdx.length > 1;

    final usedDestNames = <String>{};
    for (final idx in sortedIdx) {
      final f = files[idx];
      var destFilename = useSuffix
          ? _destFilenameWithEncodedPath(f, rootAbs)
          : p.basename(f.path);
      destFilename = _ensureUniqueDestName(destFilename, usedDestNames, f, rootAbs);
      copies.add(
        _CopyOk(
          source: f,
          destFilename: destFilename,
          srcDisplay: _displaySourceForLog(f.absolute.path, rootAbs),
        ),
      );
    }
    print('');
  }

  return (copies: copies, skippedQueries: skippedQueries);
}

String _ensureUniqueDestName(
  String destFilename,
  Set<String> usedDestNames,
  File source,
  String rootAbs,
) {
  var name = destFilename;
  var n = 2;
  while (usedDestNames.contains(name)) {
    final stem = p.basenameWithoutExtension(destFilename);
    final ext = p.extension(destFilename);
    final extra = '_${n}_${_shortHash(source.path)}';
    name = _trimFilenameForWindows('$stem$extra$ext', maxTotalChars: 200);
    n++;
  }
  usedDestNames.add(name);
  return name;
}

int _shortHash(String s) {
  var h = 5381;
  for (final c in s.codeUnits) {
    h = ((h << 5) + h + c) & 0x7fffffff;
  }
  return h;
}

String _sanitizePathSegmentForFilename(String s) {
  return s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}

/// Όνομα προορισμού: stem + '_' + parent path segments (υπό lib ή root), με όρια Windows.
String _destFilenameWithEncodedPath(File source, String projectRootAbs) {
  final normSource = p.normalize(source.absolute.path);
  final normRoot = p.normalize(projectRootAbs);
  final libRoot = p.normalize(p.join(normRoot, 'lib'));

  String rel;
  if (normSource.startsWith('$libRoot${p.separator}')) {
    rel = p.relative(normSource, from: libRoot);
  } else if (normSource.startsWith('$normRoot${p.separator}')) {
    rel = p.relative(normSource, from: normRoot);
  } else {
    return p.basename(source.path);
  }

  final relForward = rel.replaceAll('\\', '/');
  final segments = relForward.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return p.basename(source.path);

  final fileName = segments.removeLast();
  final stem = p.basenameWithoutExtension(fileName);
  final ext = p.extension(fileName);

  final sanitizedParts = segments.map(_sanitizePathSegmentForFilename).where((s) => s.isNotEmpty).toList();
  final suffix = sanitizedParts.join('_');
  final name = suffix.isEmpty ? '$stem$ext' : '$stem''_$suffix$ext';

  return _trimFilenameForWindows(name, maxTotalChars: 200);
}

/// Μέγιστο ασφαλές μήκος ονόματος αρχείου (Windows component ~255, αφήνουμε περιθώριο).
String _trimFilenameForWindows(String name, {required int maxTotalChars}) {
  if (name.length <= maxTotalChars) return name;
  final ext = p.extension(name);
  var stem = p.basenameWithoutExtension(name);
  final tag = _shortHash(name).toRadixString(16);
  final reserve = tag.length + 1 + ext.length + 2;
  var maxStem = maxTotalChars - reserve;
  if (maxStem < 16) maxStem = 16;
  if (stem.length > maxStem) {
    stem = stem.substring(0, maxStem);
  }
  return '${stem}_$tag$ext';
}

// —————————————————————————————————————————————————————————————————————
// Interactive missing (fuzzy)
// —————————————————————————————————————————————————————————————————————

_InteractivePickResult _handleMissingInteractive(
  List<String> missing,
  List<String> allFiles,
  Directory projectRoot,
  String rootAbs,
  Set<String> copiedSourceAbs,
) {
  final copies = <_CopyOk>[];
  var skippedQueries = 0;

  print('');
  print(
    '— Δεν βρέθηκαν ${missing.length} αρχεία · fuzzy προτάσεις (μετά τις αυτόματες / αμφισημία) —',
  );
  print(
    'Εντολές: αριθμοί (μία γραμμή = μία ομάδα· αν η ομάδα έχει πολλές διαδρομές, αντιγράφονται όλες με suffix), '
    '"all" για όλες τις προτάσεις, κενό = παράλειψη. Έως $_kFuzzyMaxGroups προτάσεις (ίδιο basename = μία πρόταση).',
  );
  print('');

  for (final item in missing) {
    print('Ζητούμενο: "$item"');
    final groups = _findFuzzyGroups(
      item,
      allFiles,
      projectRoot,
      copiedSourceAbs,
    );

    if (groups.isEmpty) {
      print('  (Καμία πρόταση στο project ή όλα ήδη αντιγράφηκαν.)');
      skippedQueries++;
      print('');
      continue;
    }

    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final pct = (g.bestScore * 100).round();
      if (g.isAmbiguous) {
        print(
          '  ${i + 1}. ${g.displayName}  — αμφισημία: ${g.files.length} διαδρομές  ($pct%)',
        );
        for (final f in g.files) {
          final relDisp = _displaySourceForLog(f.absolute.path, rootAbs);
          print('      · $relDisp');
        }
      } else {
        final f = g.files.single;
        final relDisp = _displaySourceForLog(f.absolute.path, rootAbs);
        print('  ${i + 1}. ${g.displayName}  ($pct%)   $relDisp');
      }
    }

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
      for (var i = 0; i < groups.length; i++) {
        indices.add(i);
      }
    } else {
      for (final part in input.split(RegExp(r'[\s,]+'))) {
        if (part.isEmpty) continue;
        final n = int.tryParse(part);
        if (n == null || n < 1 || n > groups.length) {
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
    final usedDest = <String>{};
    for (final idx in sortedIdx) {
      _appendCopiesFromFuzzyGroup(
        groups[idx],
        copies,
        copiedSourceAbs,
        usedDest,
        rootAbs,
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

final class _CopyAmbiguous extends _CopyOutcome {
  _CopyAmbiguous(this.item, this.files);

  final String item;
  final List<File> files;
}

List<_CopyOk> _dedupeCopyOkBySource(List<_CopyOk> list) {
  final seen = <String>{};
  final out = <_CopyOk>[];
  for (final ok in list) {
    final k = p.normalize(ok.source.absolute.path);
    if (seen.add(k)) out.add(ok);
  }
  return out;
}

void _copyFileToGrok(_CopyOk o, Directory grokDir, String sep) {
  final dest = File('${grokDir.path}$sep${o.destFilename}');
  o.source.copySync(dest.path);
  final destDisplay = '\\Grok\\${o.destFilename}';
  print('✓ ${o.destFilename} ← ${o.srcDisplay} → $destDisplay');
}

_CopyOutcome _resolveItem(
  String item,
  Directory projectRoot,
  String rootAbs,
  String sep,
  List<String> allFilenames,
) {
  final rootPath = projectRoot.absolute.path;
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
    if (found != null) {
      final srcDisplay = _displaySourceForLog(found.absolute.path, rootAbs);
      return _CopyOk(source: found, destFilename: destFilename, srcDisplay: srcDisplay);
    }
    return _CopyMissing(item);
  }

  final wantedBase = item.trim();
  final matches = <File>[];
  for (final rel in allFilenames) {
    if (p.basename(rel).toLowerCase() == wantedBase.toLowerCase()) {
      final f = File(p.join(rootPath, rel));
      if (f.existsSync()) matches.add(f);
    }
  }

  final byPath = <String, File>{};
  for (final f in matches) {
    byPath[p.normalize(f.absolute.path)] = f;
  }
  final files = byPath.values.toList();

  if (files.isEmpty) {
    return _CopyMissing(item);
  }
  if (files.length == 1) {
    final f = files.single;
    final df = p.basename(f.path);
    return _CopyOk(
      source: f,
      destFilename: df,
      srcDisplay: _displaySourceForLog(f.absolute.path, rootAbs),
    );
  }
  return _CopyAmbiguous(item, files);
}

void _printFinalSummary({
  required int totalCopied,
  required int automaticCopied,
  required int ambiguousCopied,
  required int fuzzyCopied,
  required int skippedAmbiguous,
  required int skippedFuzzy,
  required bool hadAmbiguous,
  required bool hadFuzzy,
}) {
  print('');
  if (totalCopied == 0 && !hadAmbiguous && !hadFuzzy) {
    print('Σύνοψη: Δεν αντιγράφηκε κανένα αρχείο.');
    return;
  }
  final parts = <String>[
    'Σύνοψη: σύνολο $totalCopied',
    'αυτόματα $automaticCopied',
    'διαδραστικά ${ambiguousCopied + fuzzyCopied}',
  ];
  if (hadAmbiguous || hadFuzzy) {
    parts.add('(αμφισημία: $ambiguousCopied · fuzzy: $fuzzyCopied)');
  }
  final skippedTotal = skippedAmbiguous + skippedFuzzy;
  if (skippedTotal > 0) {
    parts.add('παραλήφθηκαν $skippedTotal (αμφισημία: $skippedAmbiguous · fuzzy: $skippedFuzzy)');
  }
  print('${parts.join(' · ')}.');
}

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
  final raw = singleString
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty);
  final seen = <String>{};
  final out = <String>[];
  for (final s in raw) {
    if (seen.add(s)) out.add(s);
  }
  return out;
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

/// Windows: άνοιγμα του φακέλου Grok στην Εξερεύνηση αρχείων (File Explorer), ή αν υπάρχει
/// ήδη παράθυρο για την ίδια διαδρομή — ανανέωση (refresh) και εστίαση (foreground)
/// ώστε να μην πολλαπλασιάζονται παράθυρα για τον ίδιο φάκελο.
void _openOrFocusGrokInExplorer(Directory grokDir) {
  if (!Platform.isWindows) return;

  final rawPath = grokDir.absolute.path;
  final psEscapedPath = rawPath.replaceAll("'", "''");

  final script = r'''
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class _GrokExplorerNative {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
$target = [System.IO.Path]::GetFullPath('PLACEHOLDER')
$targetLower = $target.ToLowerInvariant()
$shell = New-Object -ComObject Shell.Application
$hwndLast = [IntPtr]::Zero
foreach ($w in @($shell.Windows())) {
  try {
    $doc = $w.Document
    if ($null -eq $doc) { continue }
    $folder = $doc.Folder
    if ($null -eq $folder) { continue }
    $self = $folder.Self
    if ($null -eq $self) { continue }
    $p = [System.IO.Path]::GetFullPath($self.Path)
    if ($p.ToLowerInvariant() -ne $targetLower) { continue }
    $w.Refresh()
    try { $folder.Refresh() } catch { }
    $hwndLast = [IntPtr]$w.HWND
  } catch { }
}
if ($hwndLast -ne [IntPtr]::Zero) {
  [void][_GrokExplorerNative]::ShowWindow($hwndLast, 9)
  [void][_GrokExplorerNative]::SetForegroundWindow($hwndLast)
} else {
  Start-Process explorer.exe -ArgumentList $target
}
'''.replaceAll('PLACEHOLDER', psEscapedPath);

  try {
    final r = Process.runSync(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ],
      runInShell: false,
    );
    if (r.exitCode != 0) {
      print(
        '[Grok] Προειδοποίηση: άνοιγμα φακέλου στην Εξερεύνηση — κωδικός ${r.exitCode}.',
      );
      final err = String.fromCharCodes(r.stderr).trim();
      if (err.isNotEmpty) {
        print(err);
      }
    }
  } on Object catch (e) {
    print('[Grok] Προειδοποίηση: δεν ήταν δυνατή η κλήση powershell.exe ($e).');
  }
}
