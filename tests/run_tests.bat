@echo off
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set ROOT=%SCRIPT_DIR%..

set INDIR=%ROOT%\test_data
set OUTDIR=%ROOT%\test_output
set EXPDIR=%ROOT%\tests\expected

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
set FAIL=0

for %%F in ("%INDIR%\*.bin") do (
  set NAME=%%~nF
  echo [RUN] %%~nxF  ^>  !NAME!.txt
  "%EXE%" -i "%%F" -a %BASE% --hex > "%OUTDIR%\!NAME!.txt"
  if errorlevel 1 (
    echo   [FAIL] program exited with code !errorlevel!
    set FAIL=1
  ) else (
    if exist "%EXPDIR%\!NAME!.txt" (
      fc /W "%EXPDIR%\!NAME!.txt" "%OUTDIR%\!NAME!.txt" >nul
      if errorlevel 1 (
        echo   [MISMATCH] differs from expected
        set FAIL=1
      ) else (
        echo   [OK] matches expected
      )
    ) else (
      echo   [OK] (no expected file to compare)
    )
  )
)

echo.
if %FAIL%==0 (
  echo All tests passed.
) else (
  echo Some tests FAILED. See files in "%OUTDIR%".
)
exit /b %FAIL%
