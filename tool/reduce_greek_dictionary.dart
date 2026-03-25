// ignore_for_file: avoid_print, avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../lib/core/utils/search_text_normalizer.dart';

const _subtlexUrl =
    'https://www.bcbl.eu/sites/default/files/files/SUBTLEX-GR_CD.txt';

/// Κατασκευή συμπαγούς ελληνικού λεξικού από SUBTLEX-GR_CD (+ GreekLex + IT).
///
/// Από τη ρίζα project: `dart run tool/reduce_greek_dictionary.dart`
///
/// `--subtlex=` `--greeklex=` `--it-terms=` `--out=` `--target=60000`
/// `--greeklex-extra=8000` `--rank=freq|cd|lg10cd` `--download`
Future<void> main(List<String> args) async {
  try {
    await _run(args);
  } catch (e, st) {
    print('Σφάλμα: $e\n$st');
    exitCode = 1;
  }
}

Future<void> _run(List<String> args) async {
  final projectRoot = Directory.current;
  final opts = _parseArgs(args);

  final subtlexPath = opts['subtlex'] ??
      p.join(projectRoot.path, 'tool', 'input', 'SUBTLEX-GR_CD.txt');
  var greekLexPath = opts['greeklex'] ??
      p.join(
        projectRoot.path,
        'tool',
        'input',
        'GreekLex_v101',
        'GreekLex_v101',
        'GreekLex_LowerCase.txt',
      );
  final itPath = opts['it-terms'] ??
      p.join(projectRoot.path, 'tool', 'data', 'greek_it_terms.txt');
  final outPath = opts['out'] ??
      p.join(
        projectRoot.path,
        'assets',
        'dictionaries',
        'greek_core_60k.txt',
      );

  final target = int.tryParse(opts['target'] ?? '57500') ?? 57500;
  final greekLexExtra =
      int.tryParse(opts['greeklex-extra'] ?? '4500') ?? 4500;
  final rank = opts['rank'] ?? 'freq';
  final tryDownload =
      args.contains('--download') || opts.containsKey('download');

  if (!File(subtlexPath).existsSync()) {
    if (tryDownload) {
      print('Λήψη SUBTLEX-GR_CD.txt → $subtlexPath');
      await _download(_subtlexUrl, subtlexPath);
    } else {
      print(
        'Το αρχείο SUBTLEX λείπει: $subtlexPath\n'
        'Τοποθετήστε το SUBTLEX-GR_CD.txt εκεί ή τρέξτε με --download',
      );
      exitCode = 1;
      return;
    }
  }

  if (!File(greekLexPath).existsSync()) {
    print(
      'Προειδοποίηση: GreekLex εκτός — παράλειψη συμπλήρωσης ($greekLexPath)',
    );
    greekLexPath = '';
  }

  print('SUBTLEX: $subtlexPath (rank=$rank, target=$target)');
  final merged = _loadSubtlexMerged(subtlexPath, rank: rank);
  print('  Μοναδικά κλειδιά μετά συγχώνευση: ${merged.length}');

  final entries =
      merged.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  final picked = <String>{};
  for (final e in entries) {
    if (!_isAcceptableDictionaryToken(e.key)) continue;
    picked.add(e.key);
    if (picked.length >= target) break;
  }
  print('  Επιλογή top-$target (αποδεκτά): ${picked.length}');

  if (greekLexPath.isNotEmpty) {
    var added = 0;
    final gl = _loadGreekLexSorted(greekLexPath);
    for (final e in gl) {
      if (added >= greekLexExtra) break;
      final key = SearchTextNormalizer.normalizeDictionaryForm(e.word);
      if (!_isAcceptableDictionaryToken(key) || picked.contains(key)) {
        continue;
      }
      picked.add(key);
      added++;
    }
    print('  GreekLex επιπλέον: $added');
  }

  if (File(itPath).existsSync()) {
    final itAdded = _mergeItTerms(File(itPath), picked);
    print('  IT όροι προστέθηκαν: $itAdded (σύνολο ${picked.length})');
  } else {
    print('  Προειδοποίηση: δεν βρέθηκε $itPath');
  }

  final sortedOut = picked.toList()..sort();
  Directory(p.dirname(outPath)).createSync(recursive: true);
  final sink = File(outPath).openWrite(mode: FileMode.writeOnly);
  sink.writeln(
    '# greek_core — merged SUBTLEX-GR_CD (rank=$rank) + GreekLex + IT terms',
  );
  sink.writeln('# Γραμμές λεξικού (normalizeDictionaryForm): ${sortedOut.length}');
  for (final w in sortedOut) {
    sink.writeln(w);
  }
  await sink.close();
  print('Έγγραφο: $outPath (${sortedOut.length} λέξεις)');
  print(
    'SUBTLEX-GR: Dimitropoulou et al. (2010), Frontiers in Psychology (BCBL)',
  );
  print('GreekLex: Ktori et al. (2008), Behavioral Research Methods');
}

Map<String, String> _parseArgs(List<String> args) {
  final m = <String, String>{};
  for (final a in args) {
    if (a.startsWith('--')) {
      final parts = a.substring(2).split('=');
      m[parts[0]] = parts.length == 2 ? parts[1] : '';
    }
  }
  return m;
}

Map<String, int> _loadSubtlexMerged(String path, {required String rank}) {
  final lines = File(path).readAsLinesSync(encoding: utf8);
  var pastHeader = false;
  final freqSum = <String, int>{};
  final cdSum = <String, int>{};
  final lg10cdMax = <String, double>{};

  for (final line in lines) {
    if (line.isEmpty) continue;
    if (!pastHeader) {
      if (line.contains('"Word"') && line.contains('FREQcount')) {
        pastHeader = true;
      }
      continue;
    }

    final fields = line.split('\t').map((c) => c.trim()).toList();
    if (fields.length < 4) continue;

    final rawWord = _stripQuotes(fields[1]);
    final extracted = _extractWordCandidate(rawWord);
    if (extracted == null) continue;

    final key = SearchTextNormalizer.normalizeDictionaryForm(extracted);
    if (key.isEmpty) continue;

    final f = int.tryParse(_stripQuotes(fields[2]).replaceAll(',', ''));
    final cd = int.tryParse(_stripQuotes(fields[3]).replaceAll(',', ''));
    if (f == null || cd == null) continue;

    freqSum[key] = (freqSum[key] ?? 0) + f;
    cdSum[key] = (cdSum[key] ?? 0) + cd;
    if (fields.length > 7) {
      final l10 = double.tryParse(_stripQuotes(fields[7]));
      if (l10 != null) {
        final prev = lg10cdMax[key];
        if (prev == null || l10 > prev) lg10cdMax[key] = l10;
      }
    }
  }

  final score = <String, int>{};
  for (final k in freqSum.keys) {
    switch (rank) {
      case 'cd':
        score[k] = cdSum[k] ?? 0;
        break;
      case 'lg10cd':
        final v = lg10cdMax[k] ?? 0;
        score[k] = (v * 1000000).round();
        break;
      case 'freq':
      default:
        score[k] = freqSum[k] ?? 0;
        break;
    }
  }
  return score;
}

String _stripQuotes(String s) {
  var t = s.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    t = t.substring(1, t.length - 1);
  }
  return t;
}

String? _extractWordCandidate(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final buf = StringBuffer();
  var started = false;
  for (final r in trimmed.runes) {
    final ch = String.fromCharCode(r);
    if (!started) {
      if (_isWordStartRune(r)) {
        started = true;
        buf.write(ch);
      }
    } else {
      if (_isWordContinuationRune(r)) {
        buf.write(ch);
      } else {
        break;
      }
    }
  }
  final s = buf.toString();
  return s.isEmpty ? null : s;
}

bool _isWordStartRune(int r) {
  if ((r >= 0x41 && r <= 0x5a) || (r >= 0x61 && r <= 0x7a)) return true;
  if (r >= 0x0370 && r <= 0x03ff) return true;
  return false;
}

bool _isWordContinuationRune(int r) {
  if (_isWordStartRune(r)) return true;
  if (r >= 0x30 && r <= 0x39) return true;
  if (r == 0x2d || r == 0x5f || r == 0x2b || r == 0x2e) return true;
  return false;
}

bool _isAsciiLetter(int r) =>
    (r >= 0x41 && r <= 0x5a) || (r >= 0x61 && r <= 0x7a);

bool _isGreekLowerLetter(int r) => r >= 0x03b1 && r <= 0x03c9;

bool _isAcceptableDictionaryToken(String key) {
  if (key.length < 2) return false;
  var hasLetter = false;
  for (final r in key.runes) {
    final letter = _isAsciiLetter(r) || _isGreekLowerLetter(r);
    final digit = r >= 0x30 && r <= 0x39;
    final okExtra = r == 0x2d || r == 0x5f || r == 0x2b || r == 0x2e;
    if (!letter && !digit && !okExtra) return false;
    if (letter) hasLetter = true;
  }
  return hasLetter;
}

class _GreekLexEntry {
  _GreekLexEntry(this.word, this.wordFreq);

  final String word;
  final double wordFreq;
}

List<_GreekLexEntry> _loadGreekLexSorted(String path) {
  final list = <_GreekLexEntry>[];
  var pastHeader = false;
  for (final line in File(path).readAsLinesSync(encoding: utf8)) {
    if (line.isEmpty) continue;
    if (!pastHeader) {
      if (line.startsWith('IDnr') && line.contains('WordFreq')) {
        pastHeader = true;
      }
      continue;
    }
    final parts = line.split('\t');
    if (parts.length < 5) continue;
    final word = parts[1].trim();
    final wf = double.tryParse(parts[4].trim().replaceAll(',', '.'));
    if (wf == null) continue;
    list.add(_GreekLexEntry(word, wf));
  }
  list.sort((a, b) => b.wordFreq.compareTo(a.wordFreq));
  return list;
}

int _mergeItTerms(File file, Set<String> picked) {
  var n = 0;
  for (final line in file.readAsLinesSync(encoding: utf8)) {
    var t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final hash = t.indexOf('#');
    if (hash >= 0) t = t.substring(0, hash).trim();
    if (t.isEmpty) continue;
    for (final raw in t.split(RegExp(r'\s+'))) {
      final key = SearchTextNormalizer.normalizeDictionaryForm(raw);
      if (key.length < 2) continue;
      if (!_isAcceptableDictionaryToken(key)) continue;
      if (picked.add(key)) n++;
    }
  }
  return n;
}

Future<void> _download(String url, String destPath) async {
  Directory(p.dirname(destPath)).createSync(recursive: true);
  final uri = Uri.parse(url);
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    final chunks = <int>[];
    await for (final b in response) {
      chunks.addAll(b);
    }
    File(destPath).writeAsBytesSync(chunks);
  } finally {
    client.close(force: true);
  }
}
