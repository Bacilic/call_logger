import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Αρχεία εκτός `lib/core/database/` που δικαιολογημένα αγγίζουν sqflite
/// (π.χ. desktop FFI bootstrap). Κάθε καταχώρηση απαιτεί σχόλιο αιτιολόγησης.
const _allowlistedRelativePaths = <String>{
  // sqflite FFI αρχικοποίηση (`sqfliteFfiInit`, `databaseFactory`) στην εκκίνηση desktop.
  'lib/main.dart',
};

final _sqfliteImportPattern = RegExp(
  r'''import\s+['"]package:(sqflite|sqflite_common_ffi)/''',
);

final _rawSqlPatterns = <RegExp>[
  RegExp(r'\brawQuery\s*\('),
  RegExp(r'\brawInsert\s*\('),
  RegExp(r'\brawUpdate\s*\('),
  RegExp(r'\brawDelete\s*\('),
  RegExp(r'\.execute\s*\('),
];

List<File> _dartFilesOutsideDatabaseCore(Directory libRoot) {
  if (!libRoot.existsSync()) return const [];
  return libRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) {
        final relative = p.relative(file.path, from: libRoot.parent.path);
        final normalized = relative.replaceAll(r'\', '/');
        return !normalized.startsWith('lib/core/database/');
      })
      .toList();
}

void main() {
  test('SQL isolation — sqflite μόνο μέσα σε core/database repositories', () {
    final projectRoot = Directory.current;
    final libRoot = Directory(p.join(projectRoot.path, 'lib'));
    expect(
      libRoot.existsSync(),
      isTrue,
      reason: 'Αναμένεται φάκελος lib/ στο root του project.',
    );

    final violations = <String>[];

    for (final file in _dartFilesOutsideDatabaseCore(libRoot)) {
      final relative = p
          .relative(file.path, from: projectRoot.path)
          .replaceAll(r'\', '/');
      if (_allowlistedRelativePaths.contains(relative)) continue;

      final content = file.readAsStringSync();
      final lines = content.split('\n');

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lineNo = i + 1;
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;

        if (_sqfliteImportPattern.hasMatch(line)) {
          violations.add('$relative:$lineNo — απαγορευμένο import sqflite API');
        }

        for (final pattern in _rawSqlPatterns) {
          if (pattern.hasMatch(line)) {
            violations.add(
              '$relative:$lineNo — απαγορευμένη κλήση ${pattern.pattern}',
            );
          }
        }
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Βρέθηκαν ${violations.length} παραβιάσεις του κανόνα '
        '«SQL μόνο στα Repositories του core/database/»:\n'
        '${violations.join('\n')}',
      );
    }
  });
}
