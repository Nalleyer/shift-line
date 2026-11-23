@echo off
setlocal enabledelayedexpansion

REM ---------------------------------------------------------------
REM  SHIFTLINE Windows launcher
REM    run.bat              play the game
REM    run.bat --console    play the game with console output (lovec)
REM    run.bat --test       run the headless test suite
REM    run.bat --assets     regenerate sprites / font map / audio
REM    run.bat --package    build dist\shift-line.love
REM    run.bat --help       show this help message
REM ---------------------------------------------------------------

cd /d "%~dp0"

if "%~1"=="--help" goto :help
if "%~1"=="-h" goto :help
if "%~1"=="--test" goto :test
if "%~1"=="--assets" goto :assets
if "%~1"=="--package" goto :package
if "%~1"=="--console" (
    shift
    call :find_lovec
    if errorlevel 1 goto :need_love
    "%LOVE_BIN%" . %*
    exit /b %errorlevel%
)

call :find_love
if errorlevel 1 goto :need_love
"%LOVE_BIN%" . %*
exit /b %errorlevel%

:find_love
set "LOVE_BIN="
for /f "delims=" %%i in ('where love.exe 2^>nul') do (
    if not defined LOVE_BIN set "LOVE_BIN=%%i"
)
if defined LOVE_BIN exit /b 0
if exist "%ProgramFiles%\LOVE\love.exe" (
    set "LOVE_BIN=%ProgramFiles%\LOVE\love.exe"
    exit /b 0
)
if exist "%ProgramFiles(x86)%\LOVE\love.exe" (
    set "LOVE_BIN=%ProgramFiles(x86)%\LOVE\love.exe"
    exit /b 0
)
if exist "%LocalAppData%\Programs\LOVE\love.exe" (
    set "LOVE_BIN=%LocalAppData%\Programs\LOVE\love.exe"
    exit /b 0
)
exit /b 1

:find_lovec
set "LOVE_BIN="
for /f "delims=" %%i in ('where lovec.exe 2^>nul') do (
    if not defined LOVE_BIN set "LOVE_BIN=%%i"
)
if defined LOVE_BIN exit /b 0
if exist "%ProgramFiles%\LOVE\lovec.exe" (
    set "LOVE_BIN=%ProgramFiles%\LOVE\lovec.exe"
    exit /b 0
)
if exist "%ProgramFiles(x86)%\LOVE\lovec.exe" (
    set "LOVE_BIN=%ProgramFiles(x86)%\LOVE\lovec.exe"
    exit /b 0
)
if exist "%LocalAppData%\Programs\LOVE\lovec.exe" (
    set "LOVE_BIN=%LocalAppData%\Programs\LOVE\lovec.exe"
    exit /b 0
)
goto :find_love

:need_love
echo Love2D 11.x not found. 1>&2
echo Install Love2D from https://love2d.org or via: winget install Love2d.Love2d 1>&2
exit /b 1

:test
where luajit >nul 2>nul
if errorlevel 1 (
    echo luajit is required to run the test suite. 1>&2
    exit /b 1
)
shift
luajit tests\run_all.lua %*
exit /b %errorlevel%

:assets
where node >nul 2>nul
if errorlevel 1 (
    echo node is required to regenerate assets. 1>&2
    exit /b 1
)
node tools\gen_assets.js
if errorlevel 1 exit /b %errorlevel%
node tools\gen_audio.js
exit /b %errorlevel%

:package
if not exist dist mkdir dist
if exist dist\shift-line.love del /f /q dist\shift-line.love
if exist dist\shift-line.zip del /f /q dist\shift-line.zip
powershell -NoProfile -Command "Compress-Archive -Path conf.lua, main.lua, src, assets -DestinationPath dist\shift-line.zip -Force; Move-Item -Force dist\shift-line.zip dist\shift-line.love"
if errorlevel 1 (
    echo Failed to build dist\shift-line.love 1>&2
    exit /b 1
)
echo Built dist\shift-line.love
exit /b 0

:help
echo SHIFTLINE Windows launcher
echo   run.bat              play the game
echo   run.bat --console    play the game with console output (lovec)
echo   run.bat --test       run the headless test suite
echo   run.bat --assets     regenerate sprites / font map / audio
echo   run.bat --package    build dist\shift-line.love
echo   run.bat --help       show this help message
exit /b 0
