import 'package:call_logger/core/utils/windows1253_encoder.dart';

/// Παράγει το περιεχόμενο του `install_call_logger.bat`.
class InstallerScriptBuilder {
  InstallerScriptBuilder._();

  /// Κείμενο του εγκαταστάτη (Unicode). Οι γραμμές είναι CRLF.
  ///
  /// Για εγγραφή σε δίσκο χρησιμοποιήστε [buildBytes] (Windows-1253).
  static String build() {
    // Δοκιμασμένο περιεχόμενο: chcp 1253, καθαρισμός εισόδου, goto, χωρίς /MIR|/PURGE.
    const lf = r'''@echo off
chcp 1253 >nul
setlocal EnableExtensions

set "SOURCE_ROOT=%~dp0"
if "%SOURCE_ROOT:~-1%"=="\" set "SOURCE_ROOT=%SOURCE_ROOT:~0,-1%"
set "APP_SOURCE=%SOURCE_ROOT%\current\app"

tasklist /FI "IMAGENAME eq call_logger.exe" 2>nul | find /I "call_logger.exe" >nul
if not errorlevel 1 (
  echo Η εφαρμογή τρέχει. Κλείστε την Καταγραφή Κλήσεων και ξαναδοκιμάστε.
  pause
  exit /b 1
)

if not exist "%APP_SOURCE%\call_logger.exe" (
  echo Δεν βρέθηκε το πακέτο εφαρμογής στο: %APP_SOURCE%
  pause
  exit /b 1
)

set "DEFAULT_DIR=%USERPROFILE%\Documents\Call Logger"
echo.
echo Ο προεπιλεγμένος φάκελος είναι ο:
echo   %DEFAULT_DIR%
echo Πατήστε Enter για προεπιλογή, ή πληκτρολογήστε/επικολλήστε
echo έναν διαφορετικό φάκελο (ολόκληρη τη διαδρομή).
echo.
set "INSTALL_DIR="
set /p "INSTALL_DIR=Φάκελος: "
if not defined INSTALL_DIR set "INSTALL_DIR=%DEFAULT_DIR%"

rem Καθαρισμός εισόδου: διπλά εισαγωγικά, μονά στην αρχή/τέλος, τελικό \
set "INSTALL_DIR=%INSTALL_DIR:"=%"
if not defined INSTALL_DIR set "INSTALL_DIR=%DEFAULT_DIR%"
if "%INSTALL_DIR:~0,1%"=="'" set "INSTALL_DIR=%INSTALL_DIR:~1%"
if "%INSTALL_DIR:~-1%"=="'" set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"
if "%INSTALL_DIR:~-1%"=="\" set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"
if not defined INSTALL_DIR set "INSTALL_DIR=%DEFAULT_DIR%"

if /I "%INSTALL_DIR%"=="%SOURCE_ROOT%" goto same_as_source

if exist "%INSTALL_DIR%" goto folder_ready
echo Ο φάκελος δεν υπάρχει: %INSTALL_DIR%
set /p "CREATE_DIR=Να δημιουργηθεί; (Y/N): "
if /I not "%CREATE_DIR%"=="Y" goto user_cancel
mkdir "%INSTALL_DIR%" 2>nul
if errorlevel 1 goto mkdir_failed

:folder_ready
echo.
echo Επιβεβαίωση εγκατάστασης:
echo   Φάκελος εγκατάστασης: %INSTALL_DIR%
echo   Φάκελος πηγής: %APP_SOURCE%
echo.
set /p "CONFIRM=Πατήστε Enter (ή Y) για συνέχεια, ή N για ακύρωση: "
if /I "%CONFIRM%"=="N" goto user_cancel

rem Αντιγραφή χωρίς διαγραφή υπαρχόντων φακέλων δεδομένων χρήστη.
echo Αντιγραφή αρχείων...
robocopy "%APP_SOURCE%" "%INSTALL_DIR%" /E /R:2 /W:2 /NDL /NJH /nc /ns /np
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 goto copy_failed

(
  echo {"updateFolderPath": "%SOURCE_ROOT:\=\\%"}
) > "%INSTALL_DIR%\update_source.json"

start "" "%INSTALL_DIR%\call_logger.exe"
echo Η εγκατάσταση ολοκληρώθηκε.
pause
exit /b 0

:same_as_source
echo Ο φάκελος εγκατάστασης δεν μπορεί να είναι ο φάκελος ενημερώσεων.
pause
exit /b 1

:mkdir_failed
echo Αποτυχία δημιουργίας φακέλου.
pause
exit /b 1

:copy_failed
echo Αποτυχία αντιγραφής αρχείων. κωδικός=%RC%
pause
exit /b 1

:user_cancel
echo Ακύρωση από τον χρήστη.
pause
exit /b 1
''';
    return lf.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  }

  /// Bytes του bat σε Windows-1253 (χωρίς BOM) — η μόνη σωστή μορφή εγγραφής.
  static List<int> buildBytes() => Windows1253Encoder.encode(build());
}
