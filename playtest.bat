@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Idle PD playtest

set "GODOT_BIN=C:\Users\dalto\Documents\My Games\idlrPD\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT_BIN%" (
  echo Could not find Godot at:
  echo   %GODOT_BIN%
  pause
  exit /b 1
)
if not exist "tests\run_tests.tscn" (
  echo Put playtest.bat in the spd-tactics-builds folder ^(next to project.godot^).
  pause
  exit /b 1
)

set "LOGDIR=builds\playtest"
mkdir "%LOGDIR%" 2>nul
set /a RUN=0

:loop
set /a RUN+=1
cls
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%i"
set "LOG=%LOGDIR%\playtest-%STAMP%.log"

echo Run #%RUN%   Log: %LOG%
echo This takes a few minutes.
echo.

echo ========== run_tests ==========
"%GODOT_BIN%" --headless --path . res://tests/run_tests.tscn > "%LOG%" 2>&1
set "T1=%ERRORLEVEL%"
findstr /C:"SCRIPT ERROR" "%LOG%" >nul && set "T1=1"
findstr /R /C:"^TESTS:" /C:"\[balance\]" /C:"\[boss\]" /C:"run\]" /C:"FAIL" "%LOG%"
echo run_tests exit: %T1%
echo.>> "%LOG%"
echo ========== ui_smoke ==========>> "%LOG%"

echo.
echo ========== ui_smoke ==========
"%GODOT_BIN%" --headless --path . res://tests/ui_smoke.tscn >> "%LOG%" 2>&1
set "T2=%ERRORLEVEL%"
findstr /C:"UI SMOKE:" "%LOG%" >nul || set "T2=1"
findstr /C:"UI SMOKE:" "%LOG%"
echo ui_smoke exit: %T2%

echo.
echo ==========================================
if "%T1%"=="0" (echo run_tests: PASS) else (echo run_tests: FAIL)
if "%T2%"=="0" (echo ui_smoke:  PASS) else (echo ui_smoke:  FAIL)
echo Full log: %LOG%
echo ==========================================
echo.
echo Press any key to run again, or close this window to stop.
pause >nul
goto loop
