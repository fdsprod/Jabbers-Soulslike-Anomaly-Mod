@echo off
REM Soulslike localisation report.
REM   locals.bat                 report, plus the spec that asserts it
REM   locals.bat --report        report only, skip the spec
REM   locals.bat --no-color      plain output
REM
REM Compares every MCM option label against gamedata\configs\text, in both
REM directions: a node with no translation renders as the raw string id, and a
REM translation with no node is usually a rename that left the old string
REM behind. Exit 1 on anything not already recorded in harness\mcm_labels.lua.

setlocal
cd /d "%~dp0"

set LUA=
where luajit.exe >nul 2>&1 && set LUA=luajit.exe
if "%LUA%"=="" if exist "tools\luajit.exe" set LUA=tools\luajit.exe

if "%LUA%"=="" (
    echo.
    echo ERROR: no LuaJIT found.
    echo Put luajit.exe on PATH or at tests\tools\luajit.exe.
    echo A Lua 5.1-compatible VM is required -- the module loader uses setfenv,
    echo which was removed in Lua 5.2.
    exit /b 2
)

REM --report must come first if used; everything after it is forwarded on.
set "_REPORT_ONLY="
if /i "%~1"=="--report" (
    set "_REPORT_ONLY=1"
    shift /1
)

REM Rebuild the remaining args, preserving quoting.
set "_ARGS=%1"
:collect
shift /1
if not "%~1"=="" (
    set "_ARGS=%_ARGS% %1"
    goto collect
)

REM Coloured output needs code page 65001. Remember the current one and put it
REM back on the way out -- chcp changes outlive the batch file otherwise.
set "_OLDCP="
for /f "tokens=2 delims=:" %%a in ('chcp') do set "_OLDCP=%%a"
set "_OLDCP=%_OLDCP: =%"
chcp 65001 >nul 2>&1

"%LUA%" locals.lua %_ARGS%
set "_RC=%ERRORLEVEL%"

if not defined _REPORT_ONLY (
    echo.
    "%LUA%" run.lua --file mcm_localization %_ARGS%
    if not "%ERRORLEVEL%"=="0" set "_RC=1"
)

if defined _OLDCP chcp %_OLDCP% >nul 2>&1
exit /b %_RC%
