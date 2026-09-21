@echo off
setlocal
set "HERE=%~dp0"
if exist "%HERE%GTAIV.exe" (
  set "TREX=%HERE%.trex"
) else if exist "%HERE%..\GTAIV.exe" (
  for %%I in ("%HERE%..") do set "TREX=%%~fI\.trex"
) else (
  echo Put this BAT in the GTA IV folder or .trex folder and run it.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p=Join-Path '%TREX%' 'ReShadePreset.ini'; if(!(Test-Path -LiteralPath $p)){throw 'ReShadePreset.ini not found'}; $text=[IO.File]::ReadAllText($p); $item='M3K_Sharpen@M3K_Sharpen.fx'; foreach($key in @('Techniques','TechniqueSorting')){ $m=[regex]::Match($text,'(?m)^'+$key+'=(.*)$'); if(!$m.Success){continue}; $items=@($m.Groups[1].Value.Split(',')|Where-Object{$_}); $items=@($items|Where-Object{$_ -ne $item}); $dlss=[Array]::IndexOf($items,'DLSS5_Feed@DLSS5_Feed.fx'); if($dlss -ge 0){$before=@($items[0..$dlss]);$after=@();if($dlss+1 -lt $items.Count){$after=@($items[($dlss+1)..($items.Count-1)])};$items=@($before+$item+$after)}else{$items+=$item}; $line=$key+'='+($items -join ','); $text=[regex]::Replace($text,'(?m)^'+$key+'=.*$',[System.Text.RegularExpressions.MatchEvaluator]{param($x)$line}) }; [IO.File]::WriteAllText($p,$text,[Text.UTF8Encoding]::new($false)); Write-Host 'M3K_Sharpen enabled and ordered after DLSS5_Feed.' -ForegroundColor Green"
if errorlevel 1 (
  echo Failed.
  pause
  exit /b 1
)
echo Done.
pause
