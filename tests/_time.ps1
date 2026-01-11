$ErrorActionPreference = 'Stop'
$exe = $args[0]
if ($args.Length -gt 1) { $alist = $args[1..($args.Length-1)] } else { $alist = @() }
$out = [IO.Path]::GetTempFileName()
$err = [IO.Path]::GetTempFileName()
$sw = [Diagnostics.Stopwatch]::StartNew()
Start-Process -FilePath $exe -ArgumentList $alist -NoNewWindow -Wait -RedirectStandardOutput $out -RedirectStandardError $err | Out-Null
$sw.Stop()
Remove-Item -Force $out,$err -ErrorAction SilentlyContinue | Out-Null
[Console]::WriteLine($sw.ElapsedMilliseconds)
