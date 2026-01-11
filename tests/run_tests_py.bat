@echo off
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set ROOT=%SCRIPT_DIR%..

set INDIR=%ROOT%\test_data
set OUTDIR=%ROOT%\test_output_py
set EXPDIR=%ROOT%\tests\expected

REM Prefer Windows Python launcher
set PY=py -3

set SCRIPT=%ROOT%\minidismpy\minidism.py

if not exist "%SCRIPT%" (
  echo [ERROR] Python backend not found: "%SCRIPT%"
  exit /b 2
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>nul

echo Using PY:    %PY%
echo Script:      %SCRIPT%
echo Input dir:   %INDIR%
echo Output dir:  %OUTDIR%
echo.

set BASE=0x401000
set FAIL=0

for %%F in ("%INDIR%\*.bin") do (
  set NAME=%%~nF
  echo [RUN] %%~nxF  ^>  !NAME!.txt

  %PY% "%SCRIPT%" -i "%%F" -a %BASE% --hex > "%OUTDIR%\!NAME!.txt"

  if errorlevel 1 (
    echo   [FAIL] python exited with code !errorlevel!
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
  echo All Python tests passed.
) else (
  echo Some Python tests FAILED. See files in "%OUTDIR%".
)
exit /b %FAIL%
