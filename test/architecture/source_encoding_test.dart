import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// UTF-8 encoding of U+FFFD (replacement character).
const _utf8ReplacementChar = [0xEF, 0xBF, 0xBD];

List<File> _libDartFiles(Directory libRoot) {
  if (!libRoot.existsSync()) return const [];
  return libRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

bool _containsReplacementCharBytes(List<int> bytes) {
  for (var i = 0; i <= bytes.length - 3; i++) {
    if (bytes[i] == _utf8ReplacementChar[0] &&
        bytes[i + 1] == _utf8ReplacementChar[1] &&
        bytes[i + 2] == _utf8ReplacementChar[2]) {
      return true;
    }
  }
  return false;
}

void main() {
  test(
    'lib/**/*.dart — κανένα αρχείο δεν περιέχει U+FFFD (0xEF 0xBF 0xBD)',
    () {
      final libRoot = Directory(p.join(Directory.current.path, 'lib'));
      expect(libRoot.existsSync(), isTrue, reason: 'Αναμένεται φάκελος lib/.');

      final corrupted = <String>[];
      for (final file in _libDartFiles(libRoot)) {
        final bytes = file.readAsBytesSync();
        if (_containsReplacementCharBytes(bytes)) {
          corrupted.add(
            p.relative(file.path, from: Directory.current.path)
                .replaceAll(r'\', '/'),
          );
        }
      }

      if (corrupted.isNotEmpty) {
        // ignore: avoid_print
        print('Αρχεία με U+FFFD:\n${corrupted.join('\n')}');
      }

      expect(
        corrupted,
        isEmpty,
        reason: 'Βρέθηκαν αρχεία με κατεστραμμένους χαρακτήρες UTF-8 (U+FFFD).',
      );
    },
  );
}
