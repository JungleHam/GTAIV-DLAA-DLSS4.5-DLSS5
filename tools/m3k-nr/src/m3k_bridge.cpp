// SPDX-License-Identifier: Apache-2.0
// Derived from DLSS5 ReShade AIO addon/src/nvngx-bridge.cpp at
// 09301f5528e619e8b9ec17c257d167e2985f53b0. Copyright 2026 kibblerz.
// Modifications Copyright 2026 JungleHam. See ../NOTICE and ../licenses/Apache-2.0.txt.
#include <windows.h>
#include <d3d12.h>

// The private snippet checks that its caller's module filename contains
// "nvngx.dll". m3k-nvngx.dll supplies that boundary without shadowing nvngx.dll.
// No loader, SDK facade, interception, or NGX core ownership lives in this DLL.
using Result = unsigned long;
using Init = Result (__cdecl *)(unsigned long long, const wchar_t *, ID3D12Device *, unsigned long, const void *);
using Params = Result (__cdecl *)(void *);
using Create = Result (__cdecl *)(ID3D12GraphicsCommandList *, int, void *, void **);
using Eval = Result (__cdecl *)(ID3D12GraphicsCommandList *, const void *, const void *, void *);
using Release = Result (__cdecl *)(void *);
using Shutdown = Result (__cdecl *)(ID3D12Device *);

// Keep actual call/return instructions inside this module, including Release builds.
#pragma optimize("", off)
extern "C" __declspec(dllexport) Result __cdecl M3K_Init(Init fn, unsigned long long id,
    const wchar_t *path, ID3D12Device *device, unsigned long version)
{
    if (!fn) return 0xBAD00005UL;
    volatile Result r = fn(id, path, device, version, nullptr); MemoryBarrier(); return r;
}
extern "C" __declspec(dllexport) Result __cdecl M3K_Populate(Params fn, void *params)
{
    if (!fn || !params) return 0xBAD00005UL;
    volatile Result r = fn(params); MemoryBarrier(); return r;
}
extern "C" __declspec(dllexport) Result __cdecl M3K_Create(Create fn,
    ID3D12GraphicsCommandList *list, int feature, void *params, void **handle)
{
    if (!fn) return 0xBAD00005UL;
    volatile Result r = fn(list, feature, params, handle); MemoryBarrier(); return r;
}
extern "C" __declspec(dllexport) Result __cdecl M3K_Evaluate(Eval fn,
    ID3D12GraphicsCommandList *list, const void *handle, const void *params)
{
    if (!fn) return 0xBAD00005UL;
    volatile Result r = fn(list, handle, params, nullptr); MemoryBarrier(); return r;
}
extern "C" __declspec(dllexport) Result __cdecl M3K_Release(Release fn, void *handle)
{
    if (!fn) return 0xBAD00005UL;
    volatile Result r = fn(handle); MemoryBarrier(); return r;
}
extern "C" __declspec(dllexport) Result __cdecl M3K_Shutdown(Shutdown fn, ID3D12Device *device)
{
    if (!fn) return 0xBAD00005UL;
    volatile Result r = fn(device); MemoryBarrier(); return r;
}
#pragma optimize("", on)
