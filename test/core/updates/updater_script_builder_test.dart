import 'package:call_logger/core/updates/updater_script_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdaterScriptBuilder', () {
    test('generated cmd waits for PID, backs up, overlays without MIR/PURGE, rolls back, restarts', () {
      final script = UpdaterScriptBuilder.build();

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

      // ΜΟΝΟ το PID περνά ως όρισμα (%1). Οι διαδρομές υπολογίζονται από το
      // %~dp0 — ΔΕΝ πρέπει να υπάρχουν %~2/%~3/%~4 (αυτό ήταν το σφάλμα που
      // έσπαγε τη γραμμή εντολών σε φακέλους με κενά).
      expect(script, contains('%~1'));
      expect(script, isNot(contains('%~2')));
      expect(script, isNot(contains('%~3')));
      expect(script, isNot(contains('%~4')));

      // Οι διαδρομές πηγάζουν από τον φάκελο του ίδιου του script (%~dp0).
      expect(script, contains('%~dp0'));
      expect(script.toLowerCase(), contains('set "staging_dir=%~dp0app"'));
      expect(
        script.toLowerCase(),
        contains('for %%i in ("%~dp0..") do set "install_dir=%%~fi"'),
      );

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
      expect(script, contains('updater.log'));
      expect(script, contains('FAIL'));
      expect(script, contains(':log'));
    });
  });
}
