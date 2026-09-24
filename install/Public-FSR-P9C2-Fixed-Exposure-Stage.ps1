[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'
function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "P9C.2 stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}
$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
if(-not(Test-Path -LiteralPath $vkPath)){throw "Missing generated source: $vkPath"}
$vk=[IO.File]::ReadAllText($vkPath)
$old='M3K-FSR-P9C: FSR 3.1.4 Vulkan context READY max=%ux%u depthInverted=%d RCAS=per-dispatch autoExposure=ON'
$new='M3K-FSR-P9C2: FSR 3.1.4 Vulkan context READY max=%ux%u depthInverted=%d RCAS=per-dispatch autoExposure=OFF(default exposure)'
$vk=Once $vk $old $new 'context exposure marker'
[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
Write-Host 'P9C.2 applied: FSR fixed/default exposure marker; backend header owns the actual auto-exposure disable.'
