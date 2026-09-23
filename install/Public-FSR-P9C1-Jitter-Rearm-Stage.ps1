[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "P9C.1 stage \${Label}: expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
foreach($p in @($vkPath,$FeederSource)){if(-not(Test-Path -LiteralPath $p)){throw "Missing generated source: $p"}}
$vk=[IO.File]::ReadAllText($vkPath)
$feed=[IO.File]::ReadAllText($FeederSource)

# P9C.1 is intentionally feeder-only. The hardware-proven b-bridge DLL is not
# changed. The goal is to distinguish a stale bridge config from a bridge-side
# eligible-draw miss after a live vendor transition, while giving the stale-config
# case one safe self-repair path.

$stateOld='static bool g_m3kFsrLastJitterActive=false;'
$stateNew=@'
static bool g_m3kFsrLastJitterActive=false;
static ULONGLONG g_m3kP9C1JitterInactiveSince=0;
static ULONGLONG g_m3kP9C1NextJitterReassert=0;
static UINT g_m3kP9C1JitterReassertAttempts=0;
static bool g_m3kP9C1ResizeResyncIssued=false;
'@
$vk=Once $vk $stateOld $stateNew 'jitter watchdog state'

$jitterOld=@'
    const bool jitterActive=jitterReadable&&jitter.valid&&jitter.active&&
        jitter.renderWidth==static_cast<UINT>(info.width)&&jitter.renderHeight==static_cast<UINT>(info.height);

    const bool jitterTransition=!g_m3kFsrJitterStateKnown||
'@
$jitterNew=@'
    const bool jitterActive=jitterReadable&&jitter.valid&&jitter.active&&
        jitter.renderWidth==static_cast<UINT>(info.width)&&jitter.renderHeight==static_cast<UINT>(info.height);

    const bool p9c1WatchEligible=
        g_m3kScalingTechnologyActive==2u&&g_m3kMasterEnabled&&!g_m3kMasterDisablePending&&
        !g_m3kScalingTransitionNativeOverride&&
        g_m3kDesiredRenderW==info.width&&g_m3kDesiredRenderH==info.height;

    if(p9c1WatchEligible)
    {
        const ULONGLONG p9c1Now=GetTickCount64();
        if(jitterActive)
        {
            if(g_m3kP9C1JitterInactiveSince)
                Log("M3K-P9C1: AMD jitter bridge RECOVERED after %llu ms; bridgeCfg=%ux%u rawFrame=%ld rawEpoch=%ld",
                    static_cast<unsigned long long>(p9c1Now-g_m3kP9C1JitterInactiveSince),
                    jitter.renderWidth,jitter.renderHeight,jitter.frame,jitter.epoch);
            g_m3kP9C1JitterInactiveSince=0;
            g_m3kP9C1NextJitterReassert=0;
            g_m3kP9C1JitterReassertAttempts=0;
            g_m3kP9C1ResizeResyncIssued=false;
        }
        else
        {
            if(!g_m3kP9C1JitterInactiveSince)g_m3kP9C1JitterInactiveSince=p9c1Now;
            const bool cfgMatch=jitterReadable&&jitter.valid&&
                jitter.renderWidth==info.width&&jitter.renderHeight==info.height;

            if(g_m3kP9C1JitterReassertAttempts<4u&&p9c1Now>=g_m3kP9C1NextJitterReassert)
            {
                g_m3kP9C1NextJitterReassert=p9c1Now+1000u;
                ++g_m3kP9C1JitterReassertAttempts;
                M3kWriteMasterIni(L"TemporalJitter",1);
                M3kWriteRenderSizeIni(info.width,info.height);
                M3kWritePublicUInt(L"JitterPhases",M3kComputeAutoJitterPhases());
                Log("M3K-P9C1: AMD jitter bridge inactive age=%llu ms attempt=%u; bridgeReadable=%d valid=%d rawActive=%d bridgeCfg=%ux%u source=%ux%u cfgMatch=%d; reasserted TemporalJitter/render/phases",
                    static_cast<unsigned long long>(p9c1Now-g_m3kP9C1JitterInactiveSince),
                    g_m3kP9C1JitterReassertAttempts,jitterReadable?1:0,jitter.valid?1:0,jitter.active?1:0,
                    jitter.renderWidth,jitter.renderHeight,info.width,info.height,cfgMatch?1:0);
            }

            if(!g_m3kP9C1ResizeResyncIssued&&p9c1Now-g_m3kP9C1JitterInactiveSince>=1500u)
            {
                g_m3kP9C1ResizeResyncIssued=true;
                const bool posted=M3kSignalGtaResize(info.width,info.height);
                Log("M3K-P9C1: AMD jitter still inactive after reassert; logical WM_SIZE re-arm %ux%u posted=%d bridgeCfg=%ux%u cfgMatch=%d",
                    info.width,info.height,posted?1:0,jitter.renderWidth,jitter.renderHeight,cfgMatch?1:0);
            }
        }
    }
    else
    {
        g_m3kP9C1JitterInactiveSince=0;
        g_m3kP9C1NextJitterReassert=0;
        g_m3kP9C1JitterReassertAttempts=0;
        g_m3kP9C1ResizeResyncIssued=false;
    }

    const bool jitterTransition=!g_m3kFsrJitterStateKnown||
'@
$vk=Once $vk $jitterOld $jitterNew 'AMD jitter re-arm watchdog'

$logOld=@'
        Log("M3K-FSR-P4A: exact raster handoff active=%d readable=%d bridgeFrame=%ld epoch=%ld raster=(%+.6f,%+.6f) fsr=(%+.6f,%+.6f) reset=%d",
            jitterActive?1:0,jitterReadable?1:0,jitterActive?jitter.frame:-1,jitterActive?jitter.epoch:-1,
            jitterActive?jitter.jitterX:0.0f,jitterActive?jitter.jitterY:0.0f,
            d.jitterX,d.jitterY,d.reset?1:0);
'@
$logNew=@'
        Log("M3K-FSR-P4A: exact raster handoff active=%d readable=%d bridgeFrame=%ld epoch=%ld raster=(%+.6f,%+.6f) fsr=(%+.6f,%+.6f) reset=%d",
            jitterActive?1:0,jitterReadable?1:0,jitterActive?jitter.frame:-1,jitterActive?jitter.epoch:-1,
            jitterActive?jitter.jitterX:0.0f,jitterActive?jitter.jitterY:0.0f,
            d.jitterX,d.jitterY,d.reset?1:0);
        Log("M3K-P9C1: bridge snapshot valid=%d rawActive=%d rawFrame=%ld rawEpoch=%ld bridgeCfg=%ux%u source=%ux%u cfgMatch=%d",
            jitter.valid?1:0,jitter.active?1:0,jitter.frame,jitter.epoch,
            jitter.renderWidth,jitter.renderHeight,info.width,info.height,
            (jitter.valid&&jitter.renderWidth==info.width&&jitter.renderHeight==info.height)?1:0);
'@
$vk=Once $vk $logOld $logNew 'raw bridge diagnostics'

foreach($marker in @(
    'M3K-P9C1: AMD jitter bridge inactive age=',
    'M3K-P9C1: AMD jitter bridge RECOVERED',
    'logical WM_SIZE re-arm',
    'M3K-P9C1: bridge snapshot valid='
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "P9C.1 verification marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
Write-Host 'P9C.1 applied: AMD post-switch jitter watchdog/re-arm + raw bridge diagnostics; bridge DLL unchanged.'
