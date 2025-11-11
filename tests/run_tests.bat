@echo off
setlocal enabledelayedexpansion

REM === resolve repo root (this script is in /tests) ===
set SCRIPT_DIR=%~dp0
set ROOT=%SCRIPT_DIR%..

REM === inputs, outputs, exe ===
set INDIR=%ROOT%\test_data
set OUTDIR=%ROOT%\test_output

REM If exe path passed as 1st arg, use it; else assume Debug build
if "%~1"=="" (
  set EXE=%ROOT%\minidism\Debug\minidism.exe
) else (
  set EXE=%~1
)

if not exist "%EXE%" (
  echo [ERROR] EXE not found: "%EXE%"
  echo Usage: run_tests.bat "C:\path\to\minidism.exe"
  exit /b 1
)

if not exist "%INDIR%" mkdir "%INDIR%" >nul 2>nul
if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>nul

echo Using EXE:   %EXE%
echo Input dir:   %INDIR%
echo Output dir:  %OUTDIR%
echo.

set BASE=0x401000

for %%F in ("%INDIR%\*.bin") do (
  set NAME=%%~nF
  echo [RUN] %%~nxF  ^>  !NAME!.txt
  "%EXE%" -i "%%F" -a %BASE% --hex > "%OUTDIR%\!NAME!.txt"
  if errorlevel 1 (
    echo   [FAIL] exit code !errorlevel!
  ) else (
    echo   [OK]
  )
)
echo.
echo Done. Results in %OUTDIR%.
exit /b 0
