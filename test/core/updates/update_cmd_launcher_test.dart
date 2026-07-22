// Ασφαλής εκκίνηση updater.cmd με διαδρομές που περιέχουν κενά.
//
//   flutter test test/core/updates/update_cmd_launcher_test.dart

import 'dart:io';

import 'package:call_logger/core/updates/update_cmd_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('UpdateCmdLauncher.buildCmdExeArguments', () {
    test('starts with cmd /d /c switches', () {
      final args = UpdateCmdLauncher.buildCmdExeArguments(
        r'C:\Users\V.drosos\Documents\Call Logger\.update_staging\updater.cmd',
        ['16220'],
      );
      expect(args.take(2), ['/d', '/c']);
    });

    test('passes script path and PID as distinct list elements', () {
      final args = UpdateCmdLauncher.buildCmdExeArguments(
        r'C:\Apps\Call Logger\updater.cmd',
        ['4242'],
      );
      expect(args[0], '/d');
      expect(args[1], '/c');
      expect(args[2], r'C:\Apps\Call Logger\updater.cmd');
      expect(args[3], '4242');
      // Καμία χειροποίητη μορφοποίηση εισαγωγικών / escaping.
      expect(args.length, 4);
      expect(args.any((a) => a.contains(r'\"')), isFalse);
    });

    test('does NOT use /s (which would strip the script path quotes)', () {
      final args = UpdateCmdLauncher.buildCmdExeArguments(
        r'C:\Apps\Call Logger\updater.cmd',
        ['1'],
      );
      expect(args, isNot(contains('/s')));
    });
  });

  // Πιστός έλεγχος: πραγματικό cmd.exe σε φάκελο ΜΕ ΚΕΝΟ στο όνομα.
  // Αυτός ο έλεγχος αποτυγχάνει με το παλιό μοτίβο (προ-quoted string ή
  // πολλαπλά quoted ορίσματα) και περνά μόνο με τη σωστή εκκίνηση.
  group('UpdateCmdLauncher.launchDetached (real cmd.exe)', () {
    test(
      'runs a script located in a path with spaces and passes the PID arg',
      () async {
        final tempRoot = await Directory.systemTemp.createTemp('cmd_launch_');
        // Φάκελος με κενό — ακριβώς η συνθήκη «Documents\\Call Logger».
        final spaced = Directory(p.join(tempRoot.path, 'Call Logger Test'));
        await spaced.create(recursive: true);
        final scriptPath = p.join(spaced.path, 'probe.cmd');
        final ranFile = p.join(spaced.path, 'ran.txt');

        await File(scriptPath).writeAsString(
          '@echo off\r\n'
          '> "%~dp0ran.txt" echo PID=%~1\r\n',
        );

        try {
          await UpdateCmdLauncher.launchDetached(
            scriptPath: scriptPath,
            scriptArgs: ['4242'],
            workingDirectory: spaced.path,
          );

          // Detached: δώσε λίγο χρόνο και δες αν το script όντως έτρεξε.
          final out = File(ranFile);
          var waited = 0;
          while (!await out.exists() && waited < 50) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            waited++;
          }

          expect(
            await out.exists(),
            isTrue,
            reason: 'Το script σε φάκελο με κενό δεν εκτελέστηκε — '
                'η γραμμή εντολών του cmd έσπασε.',
          );
          expect(await out.readAsString(), contains('PID=4242'));
        } finally {
          if (await tempRoot.exists()) {
            await tempRoot.delete(recursive: true);
          }
        }
      },
      skip: !Platform.isWindows,
    );
  });
}
