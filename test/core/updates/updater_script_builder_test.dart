import 'package:call_logger/core/updates/updater_script_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdaterScriptBuilder', () {
    test('generated cmd waits for PID, backs up, overlays without MIR/PURGE, rolls back, restarts', () {
      final script = UpdaterScriptBuilder.build(
        pidPlaceholder: '%~1',
        installDirPlaceholder: '%~2',
        stagingDirPlaceholder: '%~3',
        backupDirPlaceholder: '%~4',
      );

      final upper = script.toUpperCase();
      final robocopyLines = script
          .split('\n')
          .where((l) => l.toLowerCase().contains('robocopy'))
          .toList();

      expect(script, contains('@echo off'));
      // Ο updater ΔΕΝ χρησιμοποιεί chcp/ελληνικά: πρέπει να είναι καθαρά ASCII,
      // αλλιώς το batch parsing καταρρέει (όπως συνέβη με τον installer).
      expect(script, isNot(contains('chcp')));
      expect(
        script.codeUnits.every((c) => c < 128),
        isTrue,
        reason: 'Ο updater.cmd πρέπει να είναι ASCII-only',
      );
      expect(script.toLowerCase(), contains('tasklist'));
      expect(script, contains('%~1'));
      expect(script, contains('%~2'));
      expect(script, contains('%~3'));
      expect(script, contains('%~4'));

      // Backup πριν το overlay: το πρώτο robocopy πηγάζει από INSTALL, το overlay από STAGING.
      expect(script.toLowerCase(), contains('robocopy "%install_dir%" "%backup_dir%"'));
      expect(script.toLowerCase(), contains('robocopy "%staging_dir%" "%install_dir%"'));
      final backupIdx = script.toLowerCase().indexOf(
        'robocopy "%install_dir%" "%backup_dir%"',
      );
      final overlayIdx = script.toLowerCase().indexOf(
        'robocopy "%staging_dir%" "%install_dir%"',
      );
      expect(backupIdx, greaterThanOrEqualTo(0));
      expect(overlayIdx, greaterThan(backupIdx));

      for (final line in robocopyLines) {
        expect(line.toUpperCase(), isNot(contains('/MIR')));
        expect(line.toUpperCase(), isNot(contains('/PURGE')));
      }

      expect(upper, contains('ROLLBACK'));
      expect(script.toLowerCase(), contains('call_logger.exe'));
      expect(script.toLowerCase(), contains('errorlevel'));
    });
  });
}
