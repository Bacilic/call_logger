// Ασφαλής εκκίνηση updater.cmd: quoting σε διαδρομές με κενά + σημαίες
// κονσόλας που δεν προκαλούν καταιγίδα παραθύρων.
//
//   flutter test test/core/updates/update_cmd_launcher_test.dart

import 'dart:io';

import 'package:call_logger/core/updates/update_cmd_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

void main() {
  group('UpdateCmdLauncher.creationFlags', () {
    // Το σφάλμα «ατέρμονα παράθυρα τερματικού»: με DETACHED_PROCESS το cmd.exe
    // τρέχει χωρίς κονσόλα και ΚΑΘΕ παιδί του batch (tasklist, timeout,
    // robocopy) ανοίγει δικό του παράθυρο — 3 το δευτερόλεπτο στον βρόχο
    // αναμονής. Καμία παραλλαγή δεν επιτρέπεται να ξαναφέρει αυτή τη σημαία.
    test('never uses DETACHED_PROCESS (window-storm regression guard)', () {
      expect(
        UpdateCmdLauncher.creationFlags(visibleConsole: true)
            .has(DETACHED_PROCESS),
        isFalse,
      );
      expect(
        UpdateCmdLauncher.creationFlags(visibleConsole: false)
            .has(DETACHED_PROCESS),
        isFalse,
      );
    });

    test('visible console = ONE new console, hidden = windowless console', () {
      expect(
        UpdateCmdLauncher.creationFlags(visibleConsole: true),
        CREATE_NEW_CONSOLE,
      );
      expect(
        UpdateCmdLauncher.creationFlags(visibleConsole: false),
        CREATE_NO_WINDOW,
      );
    });
  });

  group('UpdateCmdLauncher.buildCommandLine', () {
    const cmdExe = r'C:\Windows\System32\cmd.exe';

    test('after /c there are EXACTLY two quote chars (cmd keeps them)', () {
      final line = UpdateCmdLauncher.buildCommandLine(
        cmdExe,
        r'C:\Users\V.drosos\Documents\Call Logger\.update_staging\updater.cmd',
        ['16220'],
      );
      final tail = line.substring(line.indexOf('/c') + 2);
      expect('"'.allMatches(tail).length, 2);
      expect(tail.trim(), startsWith('"'));
      expect(tail, contains('updater.cmd" 16220'));
    });

    test('uses /d /c without /s and without manual escaping', () {
      final line = UpdateCmdLauncher.buildCommandLine(
        cmdExe,
        r'C:\Apps\Call Logger\updater.cmd',
        ['4242'],
      );
      expect(line, contains(' /d /c '));
      expect(line, isNot(contains(' /s ')));
      expect(line, isNot(contains(r'\"')));
    });

    test('rejects args with spaces or quotes (would break the quote rule)', () {
      expect(
        () => UpdateCmdLauncher.buildCommandLine(
          cmdExe,
          r'C:\Apps\updater.cmd',
          [r'C:\path with space'],
        ),
        throwsArgumentError,
      );
      expect(
        () => UpdateCmdLauncher.buildCommandLine(
          cmdExe,
          r'C:\Apps\updater.cmd',
          ['"4242"'],
        ),
        throwsArgumentError,
      );
    });
  });

  // Πιστός έλεγχος: πραγματικό cmd.exe σε φάκελο ΜΕ ΚΕΝΟ στο όνομα, μέσω του
  // πραγματικού CreateProcess (FFI). Αποτυγχάνει με σπασμένο quoting ή σπασμένη
  // μεταφορά ορισμάτων/φακέλου εργασίας. Αόρατη κονσόλα ώστε το τρέξιμο των
  // τεστ να μην ανοίγει παράθυρα.
  group('UpdateCmdLauncher.launch (real cmd.exe)', () {
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
          await UpdateCmdLauncher.launch(
            scriptPath: scriptPath,
            scriptArgs: ['4242'],
            workingDirectory: spaced.path,
            visibleConsole: false,
          );

          // Ανεξάρτητη διεργασία: δώσε λίγο χρόνο και δες αν όντως έτρεξε.
          final out = File(ranFile);
          var waited = 0;
          while (!await out.exists() && waited < 50) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            waited++;
          }

          expect(
            await out.exists(),
            isTrue,
            reason:
                'Το script σε φάκελο με κενό δεν εκτελέστηκε — '
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
