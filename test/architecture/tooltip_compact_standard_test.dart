// Πρότυπο υποδείξεων: κείμενο μεγέθους πρότασης περνά από το CompactTooltip.
//
// Το σκέτο Tooltip απλώνει τη μεγάλη πρόταση σε όλο το πλάτος της οθόνης
// («μακαρόνι»). Ο φρουρός πιάνει `Tooltip(` με literal `message:` που είναι
// πολυγραμμικό ή μακρύτερο από το όριο. Δυναμικά μηνύματα (μεταβλητές) δεν
// ελέγχονται στατικά — αυτά τα κρίνει το code review.
//
//   flutter test test/architecture/tooltip_compact_standard_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Πάνω από τόσους χαρακτήρες literal, η υπόδειξη είναι «πρόταση ή μεγαλύτερη».
const int _maxPlainTooltipLiteralLength = 60;

/// Πόσες γραμμές μετά το `Tooltip(` ψάχνουμε το `message:` (μέχρι το `child:`).
const int _lookaheadLines = 10;

const _allowlistedRelativePaths = <String>{
  // Η ίδια η υλοποίηση του προτύπου τυλίγει το Tooltip του framework.
  'lib/core/widgets/compact_tooltip.dart',
};

final _plainTooltipPattern = RegExp(r'(?<![Cc]ompact)\bTooltip\(');
final _stringLiteralPattern = RegExp("'([^']*)'");

List<File> _dartFilesInLib(Directory libRoot) {
  if (!libRoot.existsSync()) return const [];
  return libRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

/// Το literal κείμενο του `message:` — συνενώνει διαδοχικά string literals
/// (adjacent strings) μέχρι το `child:` ή το τέλος του lookahead.
String _literalMessageAfter(List<String> lines, int tooltipLineIndex) {
  final buffer = StringBuffer();
  var inMessage = false;
  final end = tooltipLineIndex + _lookaheadLines;
  for (var i = tooltipLineIndex; i < lines.length && i <= end; i++) {
    final line = lines[i];
    if (i != tooltipLineIndex && _plainTooltipPattern.hasMatch(line)) break;
    if (inMessage &&
        (line.contains('child:') || line.trim().startsWith('),'))) {
      break;
    }
    if (line.contains('message:')) inMessage = true;
    if (!inMessage) continue;
    for (final m in _stringLiteralPattern.allMatches(line)) {
      buffer.write(m.group(1));
    }
  }
  return buffer.toString();
}

void main() {
  test('Υποδείξεις με κείμενο πρότασης περνούν από το CompactTooltip', () {
    final projectRoot = Directory.current;
    final libRoot = Directory(p.join(projectRoot.path, 'lib'));
    expect(libRoot.existsSync(), isTrue);

    final violations = <String>[];

    for (final file in _dartFilesInLib(libRoot)) {
      final relative = p
          .relative(file.path, from: projectRoot.path)
          .replaceAll(r'\', '/');
      if (_allowlistedRelativePaths.contains(relative)) continue;

      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (!_plainTooltipPattern.hasMatch(lines[i])) continue;

        final literal = _literalMessageAfter(lines, i);
        final multiline = literal.contains(r'\n');
        if (multiline || literal.length > _maxPlainTooltipLiteralLength) {
          violations.add(
            '$relative:${i + 1} — σκέτο Tooltip με κείμενο '
            '${literal.length} χαρακτήρων${multiline ? ' (πολυγραμμικό)' : ''} '
            '— χρησιμοποίησε CompactTooltip',
          );
        }
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Βρέθηκαν ${violations.length} υποδείξεις εκτός προτύπου '
        '(«κάθε υπόδειξη με κείμενο πρότασης ή μεγαλύτερο περνά από το '
        'CompactTooltip»):\n${violations.join('\n')}',
      );
    }
  });
}
