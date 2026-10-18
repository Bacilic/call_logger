@echo off
chcp 65001 >nul
setlocal

rem Απενεργοποιεί το "Use D3D driver" του TightVNC Server σε απομακρυσμένο σταθμό,
rem ώστε η εικόνα να έρχεται όρθια σε οθόνες που έχουν περιστραφεί.
rem Οδηγίες: "TightVNC σε οθόνες EIZO.md" στον ίδιο φάκελο.

set "PC=%~1"
if "%PC%"=="" set /p "PC=Όνομα ή IP σταθμού: "
if "%PC%"=="" goto :end

set "KEY=\\%PC%\HKLM\SOFTWARE\TightVNC\Server"

echo.
echo [1/5] Έλεγχος σύνδεσης με %PC%...
ping -n 1 -w 2000 %PC% >nul
if errorlevel 1 (
    echo       Ο σταθμός δεν απαντά.
    goto :fail
)

echo [2/5] Άνοιγμα Απομακρυσμένου Μητρώου...
sc \\%PC% config RemoteRegistry start= demand >nul
sc \\%PC% start RemoteRegistry >nul 2>&1
timeout /t 3 /nobreak >nul

echo [3/5] Ρύθμιση UseD3D = 0...
reg add "%KEY%" /v UseD3D /t REG_DWORD /d 0 /f
if errorlevel 1 goto :fail

echo [4/5] Επανεκκίνηση υπηρεσίας TightVNC...
sc \\%PC% stop tvnserver >nul
timeout /t 5 /nobreak >nul
sc \\%PC% start tvnserver >nul
if errorlevel 1 (
    echo       Η υπηρεσία tvnserver δεν ξεκίνησε.
    goto :fail
)

echo [5/5] Επαλήθευση...
reg query "%KEY%" /v UseD3D | find "0x0" >nul
if errorlevel 1 goto :fail

echo.
echo ΕΠΙΤΥΧΙΑ: ξανασυνδέσου με VNC στον %PC%.
goto :end

:fail
echo.
echo ΑΠΟΤΥΧΙΑ: δες τον πίνακα "Αν αποτύχει" στις οδηγίες.

:end
echo.
pause
