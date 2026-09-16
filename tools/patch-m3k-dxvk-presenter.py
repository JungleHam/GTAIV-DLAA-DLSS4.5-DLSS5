from pathlib import Path
import json

installer_path = Path('install/Install-DLSS-Full.bat')
text = installer_path.read_text(encoding='utf-8')

URL = 'https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/releases/download/m3k-dxvk-v3.0.2-a2s1b/d3d9vk_x64.dll'
HASH = '511E0C2509E1922DB2EC38940507BA956908FE6DC5FD9B3DB9FEC489DC05F297'
DXVK_COMMIT = '6b20f622a77b87b2921fe5d2c1774d2f2ba3e9b7'
CHECKPOINT = '57a8bd2ede8d7b4b721b1981bc0e8a7e6cbe084f'


def replace_once(old: str, new: str, label: str):
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly one source match, found {count}')
    text = text.replace(old, new, 1)

replace_once(
    "$NrDllHash = '4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05'",
    "$NrDllHash = '4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05'\n"
    f"$DxvkPresenterUrl = '{URL}'\n"
    f"$DxvkPresenterHash = '{HASH}'\n"
    f"$DxvkPresenterUpstreamCommit = '{DXVK_COMMIT}'",
    'presenter pins',
)

nr_block = """    Assert-SHA256 $NrDll.FullName $NrDllHash

    Write-Host \"Downloading/cloning project source into temporary folder: $Project\" -ForegroundColor DarkGray
"""
presenter_block = """    Assert-SHA256 $NrDll.FullName $NrDllHash

    Write-Host ''
    Write-Host 'Downloading the tested M3K DXVK 3.0.2 render/output presenter...' -ForegroundColor Cyan
    $DxvkPresenterTemp = Join-Path $Temp 'd3d9vk_x64.dll'
    Download-File $DxvkPresenterUrl $DxvkPresenterTemp
    Assert-SHA256 $DxvkPresenterTemp $DxvkPresenterHash

    Write-Host \"Downloading/cloning project source into temporary folder: $Project\" -ForegroundColor DarkGray
"""
replace_once(nr_block, presenter_block, 'presenter download')

replace_once(
    "foreach ($rel in @('d3d9.dll','.trex\\NvRemixBridge.exe','.trex\\dlss5-feed.addon64'",
    "foreach ($rel in @('d3d9.dll','.trex\\NvRemixBridge.exe','.trex\\d3d9vk_x64.dll','.trex\\dlss5-feed.addon64'",
    'presenter backup inclusion',
)

bridge_install = """    if ((Hash (Join-Path $Trex 'NvRemixBridge.exe')) -ne $serverHash) { Fail 'Installed x64 bridge server hash verification failed.' }
    Copy-Item -LiteralPath $Feeder -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force
"""
presenter_install = """    if ((Hash (Join-Path $Trex 'NvRemixBridge.exe')) -ne $serverHash) { Fail 'Installed x64 bridge server hash verification failed.' }
    Copy-Item -LiteralPath $DxvkPresenterTemp -Destination (Join-Path $Trex 'd3d9vk_x64.dll') -Force
    if ((Hash (Join-Path $Trex 'd3d9vk_x64.dll')) -ne $DxvkPresenterHash) { Fail 'Installed M3K DXVK presenter hash verification failed.' }
    Copy-Item -LiteralPath $Feeder -Destination (Join-Path $Trex 'dlss5-feed.addon64') -Force
"""
replace_once(bridge_install, presenter_install, 'presenter install')

replace_once(
    '    Write-Host "  NvRemixBridge.exe    $serverHash  (same pinned b-bridge commit)"',
    '    Write-Host "  NvRemixBridge.exe    $serverHash  (same pinned b-bridge commit)"\n'
    '    Write-Host "  d3d9vk_x64.dll       $DxvkPresenterHash  (M3K render/output presenter)"',
    'presenter hash output',
)

replace_once(
    '        "NvRemixBridge.exe=$serverHash",',
    '        "NvRemixBridge.exe=$serverHash",\n'
    '        "d3d9vk_x64.dll=$DxvkPresenterHash",\n'
    '        "DxvkPresenterUpstreamCommit=$DxvkPresenterUpstreamCommit",\n'
    '        "DxvkPresenterURL=$DxvkPresenterUrl",',
    'presenter receipt',
)

installer_path.write_text(text, encoding='utf-8', newline='\n')

verify = installer_path.read_text(encoding='utf-8')
for marker in (URL, HASH, '$DxvkPresenterTemp', 'Installed M3K DXVK presenter hash verification failed.', "'.trex\\d3d9vk_x64.dll'", 'DxvkPresenterUpstreamCommit='):
    if marker not in verify:
        raise RuntimeError(f'patched installer missing marker: {marker}')

manifest_path = Path('manifests/versions.json')
data = json.loads(manifest_path.read_text(encoding='utf-8'))
data['components']['m3k-dxvk-presenter'] = {
    'product': 'M3K DXVK render/output presenter for DLSS Super Resolution',
    'upstream_version': '3.0.2',
    'upstream_commit': DXVK_COMMIT,
    'project_patch_checkpoint': CHECKPOINT,
    'release_tag': 'm3k-dxvk-v3.0.2-a2s1b',
    'url': URL,
    'dll_sha256': HASH.lower(),
    'installed_path': '.trex/d3d9vk_x64.dll',
    'installed_automatically': True,
    'notes': 'Frozen M3K source-tap + A2-S1B presenter. Reads m3k-nr.ini, overrides GTA IV D3D9 render extent from RenderWidth/RenderHeight, and resizes the real presenter to OutputWidth/OutputHeight or the monitor when output is 0x0.'
}
manifest_path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8', newline='\n')
