param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$extensions = @('.md','.txt','.json','.yml','.yaml','.bat','.cmd','.ps1','.psm1','.iss','.py','.ini','.cfg','.toml','.fx','.fxh','.c','.cpp','.h','.hpp','.cs','.sh')
$urlPattern = 'https?://[^\s"''<>\)\]]+'
$bad = New-Object System.Collections.Generic.List[object]

$files = Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and
    $_.FullName -notmatch '[\\/]installer[\\/]out[\\/]' -and
    $extensions -contains $_.Extension.ToLowerInvariant()
}

foreach ($file in $files) {
    $lineNo = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $lineNo++
        foreach ($m in [regex]::Matches($line,$urlPattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $url = $m.Value.TrimEnd('.',',',';',':')
            $directBinary = $url -match '(?i)\.(zip|exe|dll|msi|7z|rar|tar|gz|tgz|bz2|xz|bat|cmd|ps1|psm1|vbs)(\?|#|$)'
            $releaseAsset = $url -match '(?i)/releases/download/'
            $codeArchive = $false
            try { $codeArchive = (([Uri]$url).Host -ieq 'codeload.github.com') } catch { $codeArchive = $false }
            if ($directBinary -or $releaseAsset -or $codeArchive) {
                $bad.Add([pscustomobject]@{
                    File = $file.FullName.Substring((Resolve-Path -LiteralPath $Root).Path.Length).TrimStart('\','/')
                    Line = $lineNo
                    Url = $url
                })
            }
        }
    }
}

if ($bad.Count -gt 0) {
    Write-Host 'Direct binary/archive/executable-script URLs found:' -ForegroundColor Red
    $bad | Format-Table -AutoSize | Out-Host
    throw "Found $($bad.Count) hard-coded direct binary/archive/executable-script URL(s)."
}

Write-Host 'PASS: no hard-coded direct ZIP/EXE/DLL/archive/executable-script download URLs were found in repository text files.' -ForegroundColor Green
