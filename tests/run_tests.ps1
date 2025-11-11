param(
  [string]$Exe = "$PSScriptRoot\..\minidism\Debug\minidism.exe",
  [string]$InDir = "$PSScriptRoot\..\test_data",
  [string]$OutDir = "$PSScriptRoot\..\test_output",
  [string]$Base = "0x401000"
)

if (!(Test-Path $Exe)) { Write-Error "EXE not found: $Exe"; exit 1 }
if (!(Test-Path $InDir)) { New-Item -ItemType Directory -Force $InDir | Out-Null }
if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }

Write-Host "Using EXE:   $Exe"
Write-Host "Input dir:   $InDir"
Write-Host "Output dir:  $OutDir"
Write-Host ""

Get-ChildItem $InDir -Filter *.bin | ForEach-Object {
  $name = $_.BaseName
  $out = Join-Path $OutDir "$name.txt"
  Write-Host "[RUN] $($_.Name) -> $name.txt"
  & $Exe -i $_.FullName -a $Base --hex | Out-File -Encoding ascii $out
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  [FAIL] exit code $LASTEXITCODE"
  } else {
    Write-Host "  [OK]"
  }
}

Write-Host "`nDone. Results in $OutDir."
