/// Παράγει το περιεχόμενο του updater `.cmd` ως κείμενο από template.
class UpdaterScriptBuilder {
  UpdaterScriptBuilder._();

  /// Ορίσματα: %1=PID, %2=φάκελος εγκατάστασης, %3=staging app, %4=backup.
  ///
  /// Μηνύματα ΜΟΝΟ ASCII (χωρίς chcp/ελληνικά): το script τρέχει αόρατο στο
  /// παρασκήνιο και τα ελληνικά+UTF-8 καταρρέουν το batch parsing.
  static String build({
    String pidPlaceholder = '%~1',
    String installDirPlaceholder = '%~2',
    String stagingDirPlaceholder = '%~3',
    String backupDirPlaceholder = '%~4',
  }) {
    return '''
@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "OLD_PID=$pidPlaceholder"
set "INSTALL_DIR=$installDirPlaceholder"
set "STAGING_DIR=$stagingDirPlaceholder"
set "BACKUP_DIR=$backupDirPlaceholder"
set "MAX_WAIT=90"
set "WAITED=0"

if "%OLD_PID%"=="" exit /b 1
if not exist "%INSTALL_DIR%\\call_logger.exe" exit /b 1
if not exist "%STAGING_DIR%\\call_logger.exe" exit /b 1

:wait_for_exit
tasklist /FI "PID eq %OLD_PID%" 2>nul | find "%OLD_PID%" >nul
if errorlevel 1 goto process_gone
timeout /t 1 /nobreak >nul
set /a WAITED+=1
if !WAITED! GEQ %MAX_WAIT% exit /b 1
goto wait_for_exit

:process_gone
if exist "%BACKUP_DIR%" rmdir /S /Q "%BACKUP_DIR%"
mkdir "%BACKUP_DIR%" >nul 2>&1

rem Backup binaries before any change.
robocopy "%INSTALL_DIR%" "%BACKUP_DIR%" call_logger.exe *.dll native_assets.json /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np
if exist "%INSTALL_DIR%\\data" robocopy "%INSTALL_DIR%\\data" "%BACKUP_DIR%\\data" /E /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np

rem Overlay without /MIR and without /PURGE: user data folders are kept.
robocopy "%STAGING_DIR%" "%INSTALL_DIR%" /E /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np
set "RC=!ERRORLEVEL!"
if !RC! GEQ 8 goto rollback

start "" "%INSTALL_DIR%\\call_logger.exe"
exit /b 0

:rollback
robocopy "%BACKUP_DIR%" "%INSTALL_DIR%" /E /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np
start "" "%INSTALL_DIR%\\call_logger.exe"
exit /b 1
''';
  }
}
