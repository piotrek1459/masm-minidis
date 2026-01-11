@echo off
setlocal ENABLEEXTENSIONS

REM ==========================================================
REM TRUE BENCHMARK (REPORT VERSION)
REM  - ASM   : --count  (decode-only)
REM  - C++   : --hex    (same as old benchmark)
REM  - PY    : --hex    (same as old benchmark)
REM  - All output silenced (no console bottleneck)
REM ==========================================================

set REPEATS=7
set BASE=0x401000

set "TEST_FILE=%~dp0..\test_data\huge_perf.bin"

set "ASM_EXE=%~dp0..\minidism\Debug\minidism.exe"
set "CPP_EXE=%~dp0..\minidismcpp\minidismcpp.exe"
set "PY_EXE=%~dp0..\minidismpy\minidism.py"

set "CSV_OUT=%~dp0true_benchmark_results.csv"
set "PS_HELPER=%~dp0_time.ps1"

REM ----------------------------------------------------------
REM Create helper PowerShell script (prints ONLY elapsed ms)
REM ----------------------------------------------------------
> "%PS_HELPER%"  echo $ErrorActionPreference = 'Stop'
>>"%PS_HELPER%" echo $exe = $args[0]
>>"%PS_HELPER%" echo if ($args.Length -gt 1) { $alist = $args[1..($args.Length-1)] } else { $alist = @() }
>>"%PS_HELPER%" echo $out = [IO.Path]::GetTempFileName()
>>"%PS_HELPER%" echo $err = [IO.Path]::GetTempFileName()
>>"%PS_HELPER%" echo $sw = [Diagnostics.Stopwatch]::StartNew()
>>"%PS_HELPER%" echo Start-Process -FilePath $exe -ArgumentList $alist -NoNewWindow -Wait -RedirectStandardOutput $out -RedirectStandardError $err ^| Out-Null
>>"%PS_HELPER%" echo $sw.Stop()
>>"%PS_HELPER%" echo Remove-Item -Force $out,$err -ErrorAction SilentlyContinue ^| Out-Null
>>"%PS_HELPER%" echo [Console]::WriteLine($sw.ElapsedMilliseconds)

echo ==========================================================
echo Benchmark: huge_perf.bin (report mix)
echo Input:   %TEST_FILE%
echo Repeats: %REPEATS%
echo Base:    %BASE%
echo ==========================================================

echo backend,mode,run,time_ms> "%CSV_OUT%"

REM ==========================================================
REM ASM: --count (decode-only)
REM ==========================================================
echo.
echo [asm-count] "%ASM_EXE%" -i "%TEST_FILE%" -a %BASE% --count
for /L %%i in (1,1,%REPEATS%) do (
  for /f %%t in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" "%ASM_EXE%" -i "%TEST_FILE%" -a %BASE% --count') do (
    echo   run %%i: %%t ms
    echo asm,count,%%i,%%t>> "%CSV_OUT%"
  )
)

REM ==========================================================
REM C++: --hex (same behavior as old benchmark)
REM ==========================================================
echo.
echo [cpp-hex] "%CPP_EXE%" -i "%TEST_FILE%" -a %BASE% --hex
for /L %%i in (1,1,%REPEATS%) do (
  for /f %%t in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" "%CPP_EXE%" -i "%TEST_FILE%" -a %BASE% --hex') do (
    echo   run %%i: %%t ms
    echo cpp,hex,%%i,%%t>> "%CSV_OUT%"
  )
)

REM ==========================================================
REM PYTHON: --hex (same behavior as old benchmark)
REM ==========================================================
echo.
echo [py-hex] py -3 "%PY_EXE%" -i "%TEST_FILE%" -a %BASE% --hex
for /L %%i in (1,1,%REPEATS%) do (
  for /f %%t in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_HELPER%" "py" -3 "%PY_EXE%" -i "%TEST_FILE%" -a %BASE% --hex') do (
    echo   run %%i: %%t ms
    echo py,hex,%%i,%%t>> "%CSV_OUT%"
  )
)

echo.
echo ----------------------------------------------------------
echo CSV saved to:
echo %CSV_OUT%
echo Helper script:
echo %PS_HELPER%
echo ----------------------------------------------------------

endlocal
