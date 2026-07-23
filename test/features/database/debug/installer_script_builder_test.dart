import 'dart:convert';

import 'package:call_logger/features/database/debug/installer_script_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InstallerScriptBuilder', () {
    late String script;
    late List<int> bytes;

    setUp(() {
      script = InstallerScriptBuilder.build();
      bytes = InstallerScriptBuilder.buildBytes();
    });

    test('buildBytes starts with ASCII @echo off and chcp 1253', () {
      final head = ascii.decode(bytes.take(40).toList());
      expect(head, startsWith('@echo off\r\nchcp 1253'));
    });

    test('buildBytes has no UTF-8 BOM', () {
      expect(bytes.length, greaterThanOrEqualTo(3));
      expect(
        bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF,
        isFalse,
        reason: 'must not start with UTF-8 BOM',
      );
    });

    test('buildBytes has no UTF-8 multibyte Greek sequences', () {
      // UTF-8 ελληνικά ξεκινούν με 0xCE/0xCF + συνέχεια 0x80–0xBF.
      for (var i = 0; i < bytes.length - 1; i++) {
        final b = bytes[i];
        if (b != 0xCE && b != 0xCF) continue;
        final next = bytes[i + 1];
        expect(
          next >= 0x80 && next <= 0xBF,
          isFalse,
          reason: 'UTF-8-like pair at $i: '
              '0x${b.toRadixString(16)} 0x${next.toRadixString(16)}',
        );
      }
    });

    test('each Greek character occupies one Windows-1253 byte', () {
      // Όλοι οι χαρακτήρες του σεναρίου είναι BMP και 1 byte στο CP1253.
      expect(bytes.length, script.length);
      for (final rune in script.runes) {
        if (rune <= 0x7F) continue;
        expect(
          rune,
          greaterThanOrEqualTo(0x0370),
          reason: 'unexpected non-ASCII U+${rune.toRadixString(16)}',
        );
      }
    });

    test('script content has chcp 1253, input cleanup, goto, Call Logger', () {
      expect(script, contains('chcp 1253'));
      expect(script, contains('%INSTALL_DIR:"=%'));
      expect(script, contains('goto same_as_source'));
      expect(script, contains(':folder_ready'));
      expect(script, contains(':mkdir_failed'));
      expect(script, contains(':copy_failed'));
      expect(script, contains(':user_cancel'));
      expect(script, contains(r'Documents\Call Logger'));
    });

    test('robocopy without /MIR and without /PURGE', () {
      final robocopyLine = script
          .split(RegExp(r'\r?\n'))
          .firstWhere((l) => l.toLowerCase().contains('robocopy'));
      expect(robocopyLine.toUpperCase(), isNot(contains('/MIR')));
      expect(robocopyLine.toUpperCase(), isNot(contains('/PURGE')));
      expect(
        robocopyLine,
        contains(
          'robocopy "%APP_SOURCE%" "%INSTALL_DIR%" /E /R:2 /W:2 /NDL /NJH /nc /ns /np',
        ),
      );
    });

    test('robocopy line does not silence file names with /NFL', () {
      final robocopyLine = script
          .split(RegExp(r'\r?\n'))
          .firstWhere((l) => l.toLowerCase().contains('robocopy'));
      expect(robocopyLine.toUpperCase(), isNot(contains('/NFL')));
    });

    test('echo progress message immediately precedes robocopy', () {
      final lines = script.split(RegExp(r'\r?\n'));
      final robocopyIndex =
          lines.indexWhere((l) => l.toLowerCase().contains('robocopy'));
      expect(robocopyIndex, greaterThan(0));
      expect(lines[robocopyIndex - 1].trim(), 'echo Αντιγραφή αρχείων...');
    });

    test('robocopy keeps summary flags but drops /NJS', () {
      final robocopyLine = script
          .split(RegExp(r'\r?\n'))
          .firstWhere((l) => l.toLowerCase().contains('robocopy'));
      expect(robocopyLine.toUpperCase(), isNot(contains('/NJS')));
      expect(robocopyLine, contains('/NDL'));
      expect(robocopyLine, contains('/NJH'));
      expect(robocopyLine, contains('/nc'));
      expect(robocopyLine, contains('/ns'));
      expect(robocopyLine, contains('/np'));
      expect(robocopyLine, contains('/E'));
      expect(robocopyLine, contains('/R:2'));
      expect(robocopyLine, contains('/W:2'));
    });

    test('every exit path is preceded by pause', () {
      final lines = script.split(RegExp(r'\r?\n'));
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim().toLowerCase();
        if (!trimmed.startsWith('exit /b')) continue;
        expect(i, greaterThan(0));
        expect(lines[i - 1].trim().toLowerCase(), 'pause');
      }
    });

    test('uses %~dp0, tasklist, update_source.json, call_logger.exe', () {
      expect(script, contains(r'%~dp0'));
      expect(script.toLowerCase(), contains('tasklist'));
      expect(script, contains('update_source.json'));
      expect(script, contains('call_logger.exe'));
    });
  });
}
