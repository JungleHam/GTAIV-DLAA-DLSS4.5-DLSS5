# A3-S5 accepted checkpoint — automatic 1485x835 startup prime

Status: **hardware-validated success** on 2026-09-16.

Frozen checkpoint branch:

- `checkpoint/a3-s5-auto-prime`
- exact commit: `57a8bd2ede8d7b4b721b1981bc0e8a7e6cbe084f`

Do not modify the checkpoint branch.

## Accepted behavior

A3-S5 keeps the accepted A3-S2 coherent draw-boundary jitter bridge unchanged and adds an automatic startup primer in the Feeder.

Cold launch flow:

1. Preserve the user's saved `SRProfile` (UQ/Q/B/P/UP).
2. Force a startup true source of `1485x835` using the supported Quality/MaxQuality NGX contract.
3. Wait until the exact A3-S2 bridge jitter handoff is active at `1485x835`.
4. Hold for 180 successful synchronized SR frames.
5. Invalidate the resolution plan and reset temporal history.
6. Automatically release to the saved `SRProfile` and its normal true source resolution.

Hardware validation used saved Ultra Performance:

- Startup prime confirmed `1485x835 -> 2560x1440`.
- A3-S2 synchronized jitter became active at prime epoch 2.
- Prime completed after 180 synchronized SR frames.
- Automatic release switched to UP `853x480 -> 2560x1440`.
- Jitter handoff continued synchronized at epoch 3.
- User visual verdict: **worked**; startup vibration was eliminated.

## Why 1485x835

Controlled hardware tests found a narrow good source-resolution band:

- `1472x828` — vibration remained.
- `1478x832` — cured vibration.
- `1485x835` — cured vibration.
- `1493x840` — vibration remained.
- `1114x835` — vibration remained, showing height alone is not sufficient.

The successful ~832–835p near-16:9 source region worked across different presenter resolutions. A3-S5 uses the already-proven `1485x835` point rather than depending on a DLSS profile name.

## Runtime hashes

Accepted A3-S2 bridge remains:

`6DD40F145A5D503624E3E05ECF0ADBAA094CF83B24278C0BB333318E3C52A912  d3d9.dll`

A3-S5 Feeder:

`C73D8D54271F55F8931F00D62A4CDF605118BEA71D7C6BEE0B61D0CA7C1CCE4B  .trex/dlss5-feed.addon64`

Stable runtime components remain unchanged:

- `2AA35EC6AAA97F2905B4517CA2C3D3C42C4A9CC54A0E46AA968071E472EAB04C  .trex/NvRemixBridge.exe`
- `A2E4BEDACE8D99BC60B5D18E958BD7E98F8887FF40EC45A8674B892E2D1FCBBC  .trex/m3k/m3k-nvngx.dll`
- `4B8D19BC3EFF58A084F5ECA7489C921501C203450169FB82FF4F649A4482BA05  .trex/m3k/nvngx_dlssnr.dll`
- `888FCC9227194FC3C75B0D8E6720562A115BE8F28D1D8A22B64823499B7C5190  .trex/d3d9vk_x64.dll`

## Non-regression rules

- Treat A3-S2 projection/jitter architecture as finished.
- Do not change jitter phase count, sign, projection math, draw-boundary c8-c11 synchronization, MV scaling, or NR math as part of startup-prime cleanup.
- If later work reintroduces cold-start vibration in any SR profile, revert to this checkpoint immediately.
- Do not replace the startup prime with a simple feature rebuild; that was already tested and did not cure the vibration.
- Do not assume Balanced itself is special; the hardware evidence points to the narrow absolute true-source resolution region instead.
