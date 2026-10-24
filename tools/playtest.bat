@echo off
setlocal EnableExtensions
rem Double-click this file, or run it from cmd. It cds to the repo root.
rem Runs, in order, and copies both to the console and a log:
rem   godot --headless --path . res://tests/run_tests.tscn
rem   godot --headless --path . res://tests/ui_smoke.tscn
rem Godot: GODOT, else GODOT_BIN, else godot on PATH (tools\build.sh), else
rem   C:\Users\dalto\Documents\My Games\idlrPD\Godot_v4.7.2-stable_win64_console.exe
rem   (the editor exe in that folder is the last fallback).
rem The console build next to a chosen editor exe is preferred so headless
rem stdout is captured. Exit code is the first suite Godot failed with.
rem A double-click waits for a key at the end. PLAYTEST_NO_PAUSE=1 skips that.
rem exit /b keeps an already-open cmd window open.

cd /d "%~dp0\.."
if errorlevel 1 goto :cd_failed
if not exist "project.godot" goto :no_repo
if not exist "%~dp0playtest.ps1" goto :no_ps1

call :find_godot
if errorlevel 1 goto :failed

call :make_log
if errorlevel 1 goto :failed

echo.
echo Running run_tests, then ui_smoke.
echo.

set "FAIL=0"

call :run_suite run_tests "res://tests/run_tests.tscn" 1
set "RC_TESTS=%SUITE_RC%"
if not "%RC_TESTS%"=="0" if "%FAIL%"=="0" set "FAIL=%RC_TESTS%"

call :run_suite ui_smoke "res://tests/ui_smoke.tscn" 0
set "RC_SMOKE=%SUITE_RC%"
if not "%RC_SMOKE%"=="0" if "%FAIL%"=="0" set "FAIL=%RC_SMOKE%"

set "RESULT=PLAYTEST: FAIL"
if "%FAIL%"=="0" set "RESULT=PLAYTEST: PASS"
echo.
echo run_tests exit %RC_TESTS%
echo ui_smoke exit %RC_SMOKE%
echo %RESULT%
echo Log: %LOG%
>>"%LOG%" echo run_tests exit %RC_TESTS%
>>"%LOG%" echo ui_smoke exit %RC_SMOKE%
>>"%LOG%" echo %RESULT%
>>"%LOG%" echo Log: %LOG%
call :pause_if_double_clicked
exit /b %FAIL%

:cd_failed
echo Could not change to the repo root from:
echo   %~dp0
call :pause_if_double_clicked
exit /b 1

:no_repo
echo playtest.bat could not find the repo root. No project.godot in:
echo   %CD%
echo Leave this script in the tools folder and double-click it, or run it from cmd.
call :pause_if_double_clicked
exit /b 1

:no_ps1
echo Missing the helper next to this script:
echo   %~dp0playtest.ps1
call :pause_if_double_clicked
exit /b 1

:failed
call :pause_if_double_clicked
exit /b 1

:run_suite
set "SUITE_RC=1"
where.exe powershell.exe >nul 2>&1
if errorlevel 1 goto :no_powershell
if "%~3"=="1" goto :run_with_header
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0playtest.ps1" -Godot "%GODOT_EXE%" -Root "%CD%" -Log "%LOG%" -Name "%~1" -Scene "%~2"
goto :run_suite_done
:run_with_header
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0playtest.ps1" -Godot "%GODOT_EXE%" -Root "%CD%" -Log "%LOG%" -Name "%~1" -Scene "%~2" -Header
:run_suite_done
set "SUITE_RC=%ERRORLEVEL%"
exit /b 0

:no_powershell
echo PowerShell was not found. Windows PowerShell is required to capture Godot's output.
set "SUITE_RC=1"
exit /b 0

:make_log
where.exe powershell.exe >nul 2>&1
if errorlevel 1 goto :no_powershell_log
set "STAMP="
for /f %%I in ('powershell.exe -NoProfile -NonInteractive -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%I"
if not defined STAMP goto :no_stamp
set "LOGDIR=%CD%\builds\playtest"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
if not exist "%LOGDIR%" goto :no_logdir
set "LOG=%LOGDIR%\playtest-%STAMP%.log"
echo Log: %LOG%
exit /b 0

:no_powershell_log
echo PowerShell was not found. Windows PowerShell is required to capture Godot's output.
exit /b 1

:no_stamp
echo Could not read a timestamp from PowerShell, so the log was not started.
exit /b 1

:no_logdir
echo Could not create the log folder:
echo   %LOGDIR%
exit /b 1

:find_godot
set "GODOT_EXE="
set "GODOT_FROM="
set "DOC_DIR=C:\Users\dalto\Documents\My Games\idlrPD"
set "DOC_CONSOLE=%DOC_DIR%\Godot_v4.7.2-stable_win64_console.exe"
set "DOC_EDITOR=%DOC_DIR%\Godot_v4.7.2-stable_win64.exe"

if defined GODOT set "GODOT_EXE=%GODOT%"
if defined GODOT set "GODOT_FROM=GODOT"
if not defined GODOT_EXE if defined GODOT_BIN set "GODOT_EXE=%GODOT_BIN%"
if not defined GODOT_FROM if defined GODOT_BIN set "GODOT_FROM=GODOT_BIN"
if defined GODOT_EXE goto :resolve_explicit

where.exe godot >nul 2>&1
if errorlevel 1 goto :try_documented
for /f "delims=" %%G in ('where.exe godot 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%G"
set "GODOT_FROM=PATH"
goto :resolve_ready

:try_documented
if exist "%DOC_CONSOLE%" goto :use_console
if exist "%DOC_EDITOR%" goto :use_editor
goto :godot_missing

:use_console
set "GODOT_EXE=%DOC_CONSOLE%"
set "GODOT_FROM=the documented console path"
goto :resolve_ready

:use_editor
set "GODOT_EXE=%DOC_EDITOR%"
set "GODOT_FROM=the documented editor path"
goto :resolve_ready

:resolve_explicit
call :strip_quotes
call :resolve_on_path
if errorlevel 1 goto :godot_bad_explicit
goto :resolve_ready

:resolve_ready
call :strip_quotes
call :prefer_console
echo Godot: %GODOT_EXE%
echo From:  %GODOT_FROM%
for %%I in ("%GODOT_EXE%") do set "GODOT_NAME=%%~nxI"
if /I "%GODOT_NAME%"=="Godot_v4.7.2-stable_win64.exe" goto :warn_editor
exit /b 0

:warn_editor
echo WARNING: This is the windowed editor binary. Headless output is often empty.
echo          Install Godot_v4.7.2-stable_win64_console.exe in the same folder,
echo          or set GODOT to that console exe.
exit /b 0

:godot_bad_explicit
echo Godot was not found at the %GODOT_FROM% path:
echo   %GODOT_EXE%
echo.
echo Set GODOT or GODOT_BIN to the full path of Godot_v4.7.2-stable_win64_console.exe.
echo Documented install:
echo   %DOC_CONSOLE%
echo   %DOC_EDITOR%
exit /b 1

:godot_missing
echo Godot 4.7.2 was not found.
echo.
echo Set GODOT or GODOT_BIN to the full path of Godot_v4.7.2-stable_win64_console.exe,
echo or put godot on PATH, the same default tools\build.sh uses.
echo.
echo This PC's documented install is:
echo   %DOC_CONSOLE%
echo   %DOC_EDITOR%
echo The editor path is also in .vscode\settings.json.
exit /b 1

:strip_quotes
if not defined GODOT_EXE exit /b 0
set "GODOT_EXE=%GODOT_EXE:"=%"
exit /b 0

:resolve_on_path
if exist "%GODOT_EXE%" exit /b 0
set "GODOT_RESOLVED="
where.exe "%GODOT_EXE%" >nul 2>&1
if errorlevel 1 exit /b 1
for /f "delims=" %%G in ('where.exe "%GODOT_EXE%" 2^>nul') do if not defined GODOT_RESOLVED set "GODOT_RESOLVED=%%G"
if not defined GODOT_RESOLVED exit /b 1
set "GODOT_EXE=%GODOT_RESOLVED%"
exit /b 0

:prefer_console
for %%I in ("%GODOT_EXE%") do set "GODOT_DIR=%%~dpI"
for %%I in ("%GODOT_EXE%") do set "GODOT_LEAF=%%~nxI"
if /I "%GODOT_LEAF%"=="Godot_v4.7.2-stable_win64_console.exe" exit /b 0
set "CONSOLE_SIBLING=%GODOT_DIR%Godot_v4.7.2-stable_win64_console.exe"
if not exist "%CONSOLE_SIBLING%" exit /b 0
echo Using the console build beside this Godot so headless output is captured.
set "GODOT_EXE=%CONSOLE_SIBLING%"
set "GODOT_FROM=%GODOT_FROM%, console build"
exit /b 0

:pause_if_double_clicked
if defined PLAYTEST_NO_PAUSE exit /b 0
echo(%CMDCMDLINE%| findstr /i /c:" /c " >nul
if errorlevel 1 exit /b 0
echo(%CMDCMDLINE%| findstr /i /c:"%~nx0" >nul
if errorlevel 1 exit /b 0
echo.
pause
exit /b 0
