import 'package:call_logger/core/utils/windows1253_encoder.dart';

/// Παράγει το περιεχόμενο του updater `.cmd`.
class UpdaterScriptBuilder {
  UpdaterScriptBuilder._();

  /// Το script δέχεται ΜΟΝΟ ένα όρισμα: `%1` = PID της παλιάς διεργασίας.
  ///
  /// Οι διαδρομές ΔΕΝ περνιούνται ως ορίσματα — υπολογίζονται από το `%~dp0`
  /// (τον φάκελο του ίδιου του script), ώστε διαδρομές με κενά (π.χ.
  /// `Documents\Call Logger`) να μη σπάνε τη γραμμή εντολών του cmd.
  ///
  /// Προϋπόθεση διάταξης (όπως τη δημιουργεί το UpdateInstallerService):
  ///   `<install>\.update_staging\updater.cmd`   → το ίδιο το script (%~dp0)
  ///   `<install>\.update_staging\app\`          → STAGING_DIR (%~dp0app)
  ///   `<install>\`                              → INSTALL_DIR (%~dp0..)
  ///   `<install>\.update_backup\`               → BACKUP_DIR
  ///
  /// Το script τρέχει σε ΟΡΑΤΗ κονσόλα (μία — βλ. UpdateCmdLauncher) και
  /// δείχνει την πρόοδο στα ελληνικά. Τα ελληνικά απαιτούν `chcp 1253` +
  /// εγγραφή σε Windows-1253 μέσω [buildBytes] — το δοκιμασμένο μοτίβο του
  /// install_call_logger.bat. ΠΟΤΕ UTF-8: καταρρέει το batch parsing.
  ///
  /// Γράφει `%~dp0updater.log` (μηνύματα ASCII) σε κάθε κρίσιμο βήμα.
  static String build({String pidPlaceholder = '%~1'}) {
    final script =
        '''
@echo off
chcp 1253 >nul
title Ενημέρωση - Καταγραφή Κλήσεων
setlocal EnableExtensions EnableDelayedExpansion

set "OLD_PID=$pidPlaceholder"
set "STAGING_DIR=%~dp0app"
for %%I in ("%~dp0..") do set "INSTALL_DIR=%%~fI"
set "BACKUP_DIR=%INSTALL_DIR%\\.update_backup"
set "MAX_WAIT=90"
set "WAITED=0"
set "LOG=%~dp0updater.log"

> "%LOG%" echo ===== updater start %DATE% %TIME% =====
call :log "PID=%OLD_PID%"
call :log "INSTALL=%INSTALL_DIR%"
call :log "STAGING=%STAGING_DIR%"
call :log "BACKUP=%BACKUP_DIR%"

echo Ενημέρωση της Καταγραφής Κλήσεων σε εξέλιξη.
echo Μην κλείσετε αυτό το παράθυρο - θα κλείσει μόνο του όταν ολοκληρωθεί.
echo.

if "%OLD_PID%"=="" (
  call :fail "EMPTY_PID"
  exit /b 1
)
if not exist "%INSTALL_DIR%\\call_logger.exe" (
  call :fail "MISSING_INSTALL_EXE"
  exit /b 1
)
if not exist "%STAGING_DIR%\\call_logger.exe" (
  call :fail "MISSING_STAGING_EXE"
  exit /b 1
)

echo Αναμονή για το κλείσιμο της εφαρμογής...
:wait_for_exit
tasklist /FI "PID eq %OLD_PID%" 2>nul | find "%OLD_PID%" >nul
if errorlevel 1 goto process_gone
timeout /t 1 /nobreak >nul
set /a WAITED+=1
if !WAITED! GEQ %MAX_WAIT% (
  call :fail "WAIT_TIMEOUT"
  exit /b 1
)
goto wait_for_exit

:process_gone
call :log "process_gone"
echo Δημιουργία αντιγράφου ασφαλείας...
if exist "%BACKUP_DIR%" rmdir /S /Q "%BACKUP_DIR%"
mkdir "%BACKUP_DIR%" >nul 2>&1
if not exist "%BACKUP_DIR%" (
  call :fail "BACKUP_MKDIR"
  exit /b 1
)

rem Backup binaries before any change.
robocopy "%INSTALL_DIR%" "%BACKUP_DIR%" call_logger.exe *.dll native_assets.json /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np
set "RC_BK=!ERRORLEVEL!"
call :log "backup_bin RC=!RC_BK!"
if !RC_BK! GEQ 8 (
  call :fail "BACKUP_ROBOCOPY_BIN"
  exit /b 1
)
if exist "%INSTALL_DIR%\\data" (
  robocopy "%INSTALL_DIR%\\data" "%BACKUP_DIR%\\data" /E /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np
  set "RC_BD=!ERRORLEVEL!"
  call :log "backup_data RC=!RC_BD!"
  if !RC_BD! GEQ 8 (
    call :fail "BACKUP_ROBOCOPY_DATA"
    exit /b 1
  )
)

rem Overlay without /MIR and without /PURGE: user data folders are kept.
echo Αντιγραφή αρχείων νέας έκδοσης...
robocopy "%STAGING_DIR%" "%INSTALL_DIR%" /E /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np
set "RC=!ERRORLEVEL!"
call :log "overlay RC=!RC!"
if !RC! GEQ 8 goto rollback

call :log "start_exe"
echo Η ενημέρωση ολοκληρώθηκε. Η εφαρμογή ξεκινά ξανά...
start "" "%INSTALL_DIR%\\call_logger.exe"
call :log "SUCCESS"
timeout /t 3 /nobreak >nul
exit /b 0

:rollback
call :log "ROLLBACK overlay_failed RC=!RC!"
echo Η αντιγραφή απέτυχε - επαναφορά της προηγούμενης έκδοσης...
robocopy "%BACKUP_DIR%" "%INSTALL_DIR%" /E /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np
start "" "%INSTALL_DIR%\\call_logger.exe"
call :fail "OVERLAY_FAILED"
exit /b 1

:log
>> "%LOG%" echo [%TIME%] %~1
goto :eof

:fail
>> "%LOG%" echo [%TIME%] FAIL %~1
echo.
echo Η ενημέρωση απέτυχε [%~1]. Λεπτομέρειες στο αρχείο updater.log
echo στον φάκελο του σεναρίου ενημέρωσης.
pause
goto :eof
''';
    return script.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  }

  /// Bytes του script σε Windows-1253 (χωρίς BOM) — η μόνη σωστή μορφή
  /// εγγραφής όσο το script περιέχει ελληνικά μηνύματα προόδου.
  static List<int> buildBytes({String pidPlaceholder = '%~1'}) =>
      Windows1253Encoder.encode(build(pidPlaceholder: pidPlaceholder));
}
