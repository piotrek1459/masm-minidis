@echo off
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set ROOT=%SCRIPT_DIR%..

set INDIR=%ROOT%\test_data
set OUTDIR=%ROOT%\test_output_cpp
set EXPDIR=%ROOT%\tests\expected

set EXE=%ROOT%\minidismcpp\minidismcpp.exe

if not exist "%EXE%" (
  echo [ERROR] C++ EXE not found: "%EXE%"
  echo Build it first:
  echo   cd "%ROOT%\minidismcpp" ^&^& build.bat
  exit /b 2
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo Using EXE:   %EXE%
echo Input dir:   %INDIR%
echo Output dir:  %OUTDIR%
echo.

set BASE=0x00401000
set FAIL=0

for %%F in ("%INDIR%\*.bin") do (
  set NAME=%%~nF
  echo [RUN] %%~nxF  ^>  !NAME!.txt

  "%EXE%" -i "%%F" -a %BASE% --hex > "%OUTDIR%\!NAME!.txt"

  if errorlevel 1 (
    echo   [FAIL] exe returned error
    set FAIL=1
  ) else (
    if exist "%EXPDIR%\!NAME!.txt" (
      fc /b "%OUTDIR%\!NAME!.txt" "%EXPDIR%\!NAME!.txt" >nul
      if errorlevel 1 (
        echo   [FAIL] output differs from expected
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
  echo All C++ tests passed.
) else (
  echo Some C++ tests FAILED. See files in "%OUTDIR%".
)
exit /b %FAIL%
