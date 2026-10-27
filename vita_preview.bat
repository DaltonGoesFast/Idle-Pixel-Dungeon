@echo off
rem Idle PD - preview the Vita build on desktop (960x544, Vita code paths on).
rem Needs the Vita branch checked out: git checkout cursor/psvita-export-7c9a
set "GODOT=C:\Users\dalto\Documents\My Games\idlrPD\Godot_v4.7.2-stable_win64.exe"
set "PROJ=%~dp0"
set IDLEPD_VITA=1
"%GODOT%" --path "%PROJ%" --resolution 960x544 --verbose %*
pause
