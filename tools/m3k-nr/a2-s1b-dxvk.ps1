[CmdletBinding()]
param(
    [string]$DxvkRoot = 'B:\Stuff\Mods\dxvk-m3k-present-probe'
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $DxvkRoot 'src\d3d9\d3d9_swapchain.cpp'
if (-not (Test-Path -LiteralPath "$DxvkRoot\.git")) { throw "Not a git checkout: $DxvkRoot" }
if (-not (Test-Path -LiteralPath $source)) { throw "Missing DXVK source: $source" }

# S1B must build on top of the already-proven A2-S0/S0.5 source-tap checkout.
$tap = Get-ChildItem -LiteralPath (Join-Path $DxvkRoot 'src\d3d9') -File -Recurse |
    Select-String -SimpleMatch 'M3K_QueryPresentSourceV1' -List -ErrorAction SilentlyContinue
if (-not $tap) {
    throw 'This DXVK checkout does not contain M3K_QueryPresentSourceV1. Refusing to patch a vanilla/wrong checkout.'
}

$text = [IO.File]::ReadAllText($source)
if ($text.Contains('[M3K-S1B] config')) {
    Write-Host 'A2-S1B DXVK resolution patch is already present.'
    exit 0
}

$backup = "$source.M3K-S1B-prepatch"
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $source -Destination $backup
    Write-Host "Backup: $backup"
}

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = 0
    $pos = 0
    while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) {
        $count++
        $pos = $i + $Old.Length
    }
    if ($count -ne 1) { throw "${Label}: expected exactly one match, found $count" }
    return $Text.Replace($Old, $New)
}

$anchorOld = @'
namespace dxvk {

  static uint16_t MapGammaControlPoint(float x) {
'@

$anchorNew = @'
namespace dxvk {

#ifdef _WIN32
  // A2-S1B: decouple GTA's D3D9 render extent from the real window/presenter extent.
  // The same .trex\m3k-nr.ini used by the Feeder owns these settings so the two
  // halves cannot silently disagree about the requested render/output split.
  struct M3kResolutionConfig {
    uint32_t renderWidth = 0;
    uint32_t renderHeight = 0;
    uint32_t outputWidth = 0;
    uint32_t outputHeight = 0;
    bool autoResize = false;
  };

  static int g_m3kResolutionAnchor = 0;
  static volatile LONG g_m3kResizePending = 0;

  static bool M3kResolutionConfigPath(wchar_t* path, size_t pathCount) {
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCWSTR>(&g_m3kResolutionAnchor), &module))
      return false;

    DWORD length = GetModuleFileNameW(module, path, DWORD(pathCount));
    if (!length || length >= pathCount)
      return false;

    wchar_t* slash = wcsrchr(path, L'\\');
    if (!slash)
      return false;

    static const wchar_t name[] = L"m3k-nr.ini";
    const size_t prefix = size_t(slash + 1 - path);
    if (prefix + (sizeof(name) / sizeof(name[0])) > pathCount)
      return false;

    lstrcpyW(slash + 1, name);
    return true;
  }

  static M3kResolutionConfig M3kGetResolutionConfig() {
    static M3kResolutionConfig config;
    static ULONGLONG nextPoll = 0;
    static bool first = true;
    static M3kResolutionConfig last;

    const ULONGLONG now = GetTickCount64();
    if (now < nextPoll)
      return config;
    nextPoll = now + 1000;

    wchar_t path[MAX_PATH] = { };
    M3kResolutionConfig next;
    if (M3kResolutionConfigPath(path, MAX_PATH)) {
      next.renderWidth  = GetPrivateProfileIntW(L"M3K", L"RenderWidth", 0, path);
      next.renderHeight = GetPrivateProfileIntW(L"M3K", L"RenderHeight", 0, path);
      next.outputWidth  = GetPrivateProfileIntW(L"M3K", L"OutputWidth", 0, path);
      next.outputHeight = GetPrivateProfileIntW(L"M3K", L"OutputHeight", 0, path);
      next.autoResize   = GetPrivateProfileIntW(L"M3K", L"AutoResizeWindow", 0, path) != 0;
    }

    const bool changed =
      next.renderWidth  != last.renderWidth  || next.renderHeight != last.renderHeight ||
      next.outputWidth  != last.outputWidth  || next.outputHeight != last.outputHeight ||
      next.autoResize   != last.autoResize;

    config = next;
    if (first || changed) {
      Logger::info(str::format(
        "[M3K-S1B] config render=", config.renderWidth, "x", config.renderHeight,
        " output=", config.outputWidth, "x", config.outputHeight,
        " (0=monitor) autoResize=", config.autoResize ? 1 : 0));
      last = config;
      first = false;
    }
    return config;
  }

  static void M3kApplyRenderOverride(D3DPRESENT_PARAMETERS* params) {
    if (!params || !params->Windowed)
      return;

    const auto config = M3kGetResolutionConfig();
    if (!config.renderWidth || !config.renderHeight)
      return;

    if (params->BackBufferWidth != config.renderWidth ||
        params->BackBufferHeight != config.renderHeight) {
      Logger::info(str::format(
        "[M3K-S1B] D3D9 backbuffer override ",
        params->BackBufferWidth, "x", params->BackBufferHeight,
        " -> ", config.renderWidth, "x", config.renderHeight));
    }

    params->BackBufferWidth = config.renderWidth;
    params->BackBufferHeight = config.renderHeight;
  }

  struct M3kResizeJob {
    HWND window;
    uint32_t width;
    uint32_t height;
    RECT monitorRect;
  };

  static DWORD WINAPI M3kResizeWorker(void* opaque) {
    M3kResizeJob* job = static_cast<M3kResizeJob*>(opaque);
    if (job && IsWindow(job->window)) {
      RECT client = { }, outer = { };
      POINT clientOrigin = { 0, 0 };

      if (GetClientRect(job->window, &client) &&
          GetWindowRect(job->window, &outer) &&
          ClientToScreen(job->window, &clientOrigin)) {
        const int clientW = client.right - client.left;
        const int clientH = client.bottom - client.top;
        const int outerW = outer.right - outer.left;
        const int outerH = outer.bottom - outer.top;
        const int leftInset = clientOrigin.x - outer.left;
        const int topInset = clientOrigin.y - outer.top;
        const int borderW = outerW - clientW;
        const int borderH = outerH - clientH;

        SetWindowPos(
          job->window, nullptr,
          job->monitorRect.left - leftInset,
          job->monitorRect.top - topInset,
          int(job->width) + borderW,
          int(job->height) + borderH,
          SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
      }
    }

    if (job)
      HeapFree(GetProcessHeap(), 0, job);
    InterlockedExchange(&g_m3kResizePending, 0);
    return 0;
  }

  static void M3kScheduleAutoResize(HWND window, BOOL windowed) {
    if (!window || !windowed)
      return;

    const auto config = M3kGetResolutionConfig();
    if (!config.autoResize)
      return;

    HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitorInfo = { };
    monitorInfo.cbSize = sizeof(monitorInfo);
    if (!monitor || !GetMonitorInfoW(monitor, &monitorInfo))
      return;

    const uint32_t monitorW = uint32_t(monitorInfo.rcMonitor.right - monitorInfo.rcMonitor.left);
    const uint32_t monitorH = uint32_t(monitorInfo.rcMonitor.bottom - monitorInfo.rcMonitor.top);
    const uint32_t desiredW = config.outputWidth  ? config.outputWidth  : monitorW;
    const uint32_t desiredH = config.outputHeight ? config.outputHeight : monitorH;
    if (!desiredW || !desiredH)
      return;

    RECT client = { };
    POINT origin = { 0, 0 };
    if (!GetClientRect(window, &client) || !ClientToScreen(window, &origin))
      return;

    const uint32_t currentW = uint32_t(client.right - client.left);
    const uint32_t currentH = uint32_t(client.bottom - client.top);
    if (currentW == desiredW && currentH == desiredH &&
        origin.x == monitorInfo.rcMonitor.left && origin.y == monitorInfo.rcMonitor.top)
      return;

    if (InterlockedCompareExchange(&g_m3kResizePending, 1, 0) != 0)
      return;

    auto* job = static_cast<M3kResizeJob*>(
      HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(M3kResizeJob)));
    if (!job) {
      InterlockedExchange(&g_m3kResizePending, 0);
      return;
    }

    job->window = window;
    job->width = desiredW;
    job->height = desiredH;
    job->monitorRect = monitorInfo.rcMonitor;

    Logger::info(str::format(
      "[M3K-S1B] scheduling window client ",
      currentW, "x", currentH, " -> ", desiredW, "x", desiredH,
      " (monitor ", monitorW, "x", monitorH, ")"));

    HANDLE thread = CreateThread(nullptr, 0, M3kResizeWorker, job, 0, nullptr);
    if (!thread) {
      HeapFree(GetProcessHeap(), 0, job);
      InterlockedExchange(&g_m3kResizePending, 0);
      return;
    }
    CloseHandle(thread);
  }
#endif

  static uint16_t MapGammaControlPoint(float x) {
'@

$presentOld = @'
    if (m_window != window) {
      m_window = window;
      m_displayRefreshRateDirty = true;
    }

    if (!UpdateWindowCtx())
'@

$presentNew = @'
    if (m_window != window) {
      m_window = window;
      m_displayRefreshRateDirty = true;
    }

#ifdef _WIN32
    M3kScheduleAutoResize(window, m_presentParams.Windowed);
#endif

    if (!UpdateWindowCtx())
'@

$normalizeOld = @'
    if (env::getEnvVar("DXVK_FORCE_WINDOWED") == "1")
      pPresentParams->Windowed = TRUE;
  }
'@

$normalizeNew = @'
    if (env::getEnvVar("DXVK_FORCE_WINDOWED") == "1")
      pPresentParams->Windowed = TRUE;

#ifdef _WIN32
    M3kApplyRenderOverride(pPresentParams);
#endif
  }
'@

$text = Replace-ExactOnce $text $anchorOld $anchorNew 'helper insertion'
$text = Replace-ExactOnce $text $presentOld $presentNew 'Present auto-resize insertion'
$text = Replace-ExactOnce $text $normalizeOld $normalizeNew 'NormalizePresentParameters render override'

[IO.File]::WriteAllText($source, $text, (New-Object Text.UTF8Encoding($false)))

if (-not ([IO.File]::ReadAllText($source).Contains('[M3K-S1B] config'))) {
    throw 'Patch write verification failed'
}

Write-Host 'A2-S1B DXVK source patch APPLIED.'
Write-Host 'Preserved existing source-tap modifications; no reset/checkout was performed.'
Write-Host "Patched: $source"
