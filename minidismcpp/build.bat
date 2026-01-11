@echo off
setlocal

REM Build standalone C++ CLI disassembler
REM Requires g++ in PATH (MinGW-w64 / MSYS2 recommended)

cd /d %~dp0

g++ -O2 -std=c++17 -Wall -Wextra -pedantic ^
  minidismcpp.cpp ^
  -o minidismcpp.exe

if errorlevel 1 (
  echo Build failed.
  exit /b 1
)

echo Built: %cd%\minidismcpp.exe
endlocal
