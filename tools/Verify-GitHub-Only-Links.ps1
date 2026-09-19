param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$extensions = @('.md','.txt','.json','.yml','.yaml','.bat','.cmd','.ps1','.psm1','.iss','.py','.ini','.cfg','.toml','.fx','.fxh','.c','.cpp','.h','.hpp','.cs','.sh')
$urlPattern = 'https?://[^\s"''<>\)\]]+'
$bad = New-Object System.Collections.Generic.List[object]
$allowedHosts = @(
    'github.com',
    'api.github.com'
)

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
            try { $host = ([Uri]$url).Host.ToLowerInvariant() } catch { continue }
            if ($allowedHosts -notcontains $host) {
                $bad.Add([pscustomobject]@{
                    File = $file.FullName.Substring((Resolve-Path -LiteralPath $Root).Path.Length).TrimStart('\\','/')
                    Line = $lineNo
                    Host = $host
                    Url = $url
                })
            }
        }
    }
}

if ($bad.Count -gt 0) {
    Write-Host 'Non-GitHub hyperlinks found:' -ForegroundColor Red
    $bad | Format-Table -AutoSize | Out-Host
    throw "Found $($bad.Count) non-GitHub hyperlink(s)."
}

Write-Host 'PASS: every HTTP/HTTPS hyperlink in repository text points to GitHub/GitHub-owned content hosts.' -ForegroundColor Green
