@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ==========================================================
REM bench_backends.bat
REM Bench ASM vs C++ vs Python backends on huge_perf.bin
REM - prints avg/min/max (ms)
REM - writes CSV: tests\bench_results.csv
REM ==========================================================

set SCRIPT_DIR=%~dp0
set ROOT=%SCRIPT_DIR%..

set BIN=%ROOT%\test_data\huge_perf.bin
set BASE=0x401000

set ASM_EXE=%ROOT%\minidism\Debug\minidism.exe
set CPP_EXE=%ROOT%\minidismcpp\minidismcpp.exe
set PY=py -3
set PY_SCRIPT=%ROOT%\minidismpy\minidism.py

REM Output is redirected to NUL to measure pure runtime
set OUT_REDIRECT=^>NUL

REM Change this if you want more/less repeats
set REPEATS=7

set CSV=%SCRIPT_DIR%bench_results.csv

if not exist "%BIN%" (
  echo [ERROR] Missing input: "%BIN%"
  exit /b 2
)

if not exist "%ASM_EXE%" (
  echo [ERROR] Missing ASM exe: "%ASM_EXE%"
  exit /b 2
)

if not exist "%CPP_EXE%" (
  echo [ERROR] Missing C++ exe: "%CPP_EXE%"
  exit /b 2
)

if not exist "%PY_SCRIPT%" (
  echo [ERROR] Missing Python script: "%PY_SCRIPT%"
  exit /b 2
)

echo ==========================================================
echo Benchmark: huge_perf.bin
echo Input:   %BIN%
echo Repeats: %REPEATS%
echo Base:    %BASE%
echo ==========================================================
echo.

REM Write CSV header
> "%CSV%" echo backend,run_ms

call :bench_one "asm"  "%ASM_EXE% -i \"%BIN%\" -a %BASE% --hex %OUT_REDIRECT%"
call :bench_one "cpp"  "%CPP_EXE% -i \"%BIN%\" -a %BASE% --hex %OUT_REDIRECT%"
call :bench_one "py"   "%PY% \"%PY_SCRIPT%\" -i \"%BIN%\" -a %BASE% --hex %OUT_REDIRECT%"

echo.
echo CSV saved to: %CSV%
exit /b 0

REM ----------------------------------------------------------
REM bench_one <name> <command_string>
REM Uses PowerShell Measure-Command, repeats REPEATS times.
REM Appends each run to CSV, prints avg/min/max.
REM ----------------------------------------------------------
:bench_one
set NAME=%~1
set CMD=%~2

echo [%NAME%] %CMD%
echo.

set SUM=0
set MIN=999999999
set MAX=0

for /L %%I in (1,1,%REPEATS%) do (
  for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command ^
    "$t = Measure-Command { cmd /c %CMD% }; [int]$t.TotalMilliseconds"`) do (
    set MS=%%T
  )

  REM Append to CSV
  >> "%CSV%" echo %NAME%,!MS!

  REM Update stats
  set /a SUM=!SUM!+!MS!
  if !MS! LSS !MIN! set MIN=!MS!
  if !MS! GTR !MAX! set MAX=!MS!

  echo   run %%I: !MS! ms
)

set /a AVG=!SUM!/%REPEATS%
echo.
echo   avg: !AVG! ms
echo   min: !MIN! ms
echo   max: !MAX! ms
echo ----------------------------------------------------------
echo.
goto :eof
