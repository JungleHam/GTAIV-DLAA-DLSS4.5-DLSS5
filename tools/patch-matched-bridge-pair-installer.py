from pathlib import Path

path = Path("install/Install-DLSS-Full.bat")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str):
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one source match, found {count}")
    text = text.replace(old, new, 1)


old_build = r"""        SetupVS -Platform x86
        & meson setup --buildtype release --backend ninja _compDLSSFull --debug
        if ($LASTEXITCODE -ne 0) { Fail "Meson setup failed: $LASTEXITCODE" }
        Copy-Item .\Directory.Build.Props -Destination .\_compDLSSFull -Force
        & meson compile -C _compDLSSFull d3d9
        if ($LASTEXITCODE -ne 0) { Fail "Temporal-synchronization bridge build failed: $LASTEXITCODE" }
"""
new_build = r"""        SetupVS -Platform x86
        & meson setup --buildtype release --backend ninja _compDLSSFull32 --debug
        if ($LASTEXITCODE -ne 0) { Fail "x86 bridge client Meson setup failed: $LASTEXITCODE" }
        Copy-Item .\Directory.Build.Props -Destination .\_compDLSSFull32 -Force
        & meson compile -C _compDLSSFull32 d3d9
        if ($LASTEXITCODE -ne 0) { Fail "Temporal-synchronization x86 bridge client build failed: $LASTEXITCODE" }

        # b-bridge requires the 32-bit client and 64-bit server to report the same
        # source version. Build the server from this exact pinned checkout too;
        # keeping the older DLAA release server causes an immediate startup abort.
        SetupVS -Platform x64
        & meson setup --buildtype release --backend ninja _compDLSSFull64 --debug
        if ($LASTEXITCODE -ne 0) { Fail "x64 bridge server Meson setup failed: $LASTEXITCODE" }
        Copy-Item .\Directory.Build.Props -Destination .\_compDLSSFull64 -Force
        & meson compile -C _compDLSSFull64 NvRemixBridge
        if ($LASTEXITCODE -ne 0) { Fail "Matched x64 NvRemixBridge server build failed: $LASTEXITCODE" }
"""
replace_once(old_build, new_build, "dual-architecture bridge build")

old_outputs = r"""    $Bridge = Join-Path $BBridge '_compDLSSFull\src\client\d3d9.dll'
    if (-not (Test-Path -LiteralPath $Bridge)) { Fail 'Temporal-synchronization bridge d3d9.dll output is missing.' }

    $bridgeHash = Hash $Bridge
    $feederHash = Hash $Feeder
"""
new_outputs = r"""    $Bridge = Join-Path $BBridge '_compDLSSFull32\src\client\d3d9.dll'
    $BridgeServer = Join-Path $BBridge '_compDLSSFull64\src\server\NvRemixBridge.exe'
    if (-not (Test-Path -LiteralPath $Bridge)) { Fail 'Temporal-synchronization x86 bridge d3d9.dll output is missing.' }
    if (-not (Test-Path -LiteralPath $BridgeServer)) { Fail 'Matched x64 NvRemixBridge.exe output is missing.' }

    $bridgeHash = Hash $Bridge
    $serverHash = Hash $BridgeServer
    $feederHash = Hash $Feeder
"""
replace_once(old_outputs, new_outputs, "bridge outputs")

replace_once(
    '    Write-Host "  d3d9.dll             $bridgeHash"',
    '    Write-Host "  d3d9.dll             $bridgeHash"\n    Write-Host "  NvRemixBridge.exe    $serverHash  (same pinned b-bridge commit)"',
    "server hash output",
)

replace_once(
    "foreach ($rel in @('d3d9.dll','.trex\\dlss5-feed.addon64'",
    "foreach ($rel in @('d3d9.dll','.trex\\NvRemixBridge.exe','.trex\\dlss5-feed.addon64'",
    "server backup inclusion",
)

old_install = "    Copy-Item -LiteralPath $Bridge -Destination (Join-Path $Game 'd3d9.dll') -Force"
new_install = r"""    Copy-Item -LiteralPath $Bridge -Destination (Join-Path $Game 'd3d9.dll') -Force
    Copy-Item -LiteralPath $BridgeServer -Destination (Join-Path $Trex 'NvRemixBridge.exe') -Force
    if ((Hash (Join-Path $Game 'd3d9.dll')) -ne $bridgeHash) { Fail 'Installed x86 bridge client hash verification failed.' }
    if ((Hash (Join-Path $Trex 'NvRemixBridge.exe')) -ne $serverHash) { Fail 'Installed x64 bridge server hash verification failed.' }"""
replace_once(old_install, new_install, "matched bridge install")

replace_once(
    '        "d3d9.dll=$bridgeHash",',
    '        "d3d9.dll=$bridgeHash",\n        "NvRemixBridge.exe=$serverHash",',
    "server receipt hash",
)

path.write_text(text, encoding="utf-8", newline="\n")

verify = path.read_text(encoding="utf-8")
for marker in (
    "_compDLSSFull32",
    "_compDLSSFull64",
    "SetupVS -Platform x64",
    "NvRemixBridge.exe=$serverHash",
    "Installed x64 bridge server hash verification failed.",
):
    if marker not in verify:
        raise RuntimeError(f"Patched installer missing marker: {marker}")
