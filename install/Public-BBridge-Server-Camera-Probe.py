#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-Server-Camera-Probe.py <b-bridge-root>")

root = Path(sys.argv[1])
source = root / "src" / "server" / "main.cpp"
if not source.is_file():
    raise SystemExit(f"missing b-bridge server source: {source}")

text = source.read_text(encoding="utf-8")
if "M3K-CAMERA-P5C" in text:
    print("P5C server camera probe already present")
    raise SystemExit(0)

include_anchor = "#include <array>\n"
include_new = "#include <array>\n#include <cmath>\n#include <cstring>\n"
if text.count(include_anchor) != 1:
    raise SystemExit(f"include anchor count={text.count(include_anchor)}, expected 1")
text = text.replace(include_anchor, include_new, 1)

anchor = "void ProcessDeviceCommandQueue() {\n"
if text.count(anchor) != 1:
    raise SystemExit(f"ProcessDeviceCommandQueue anchor count={text.count(anchor)}, expected 1")

helpers = r'''
// M3K-CAMERA-P5C: server-only, read-only GTA IV projection telemetry.
//
// The hardware-proven 32-bit production d3d9.dll is deliberately NOT modified.
// The bridge server can query the D3D9 device state that it already owns, so this
// probe reads c0-c15 + viewport immediately before selected draws and derives:
//
//   Projection = ViewInverse * inverse(World) * WorldViewProjection
//
// GTA IV PC shader metadata identifies common world shaders as:
//   c0-c3   = row-major gWorld
//   c8-c11  = row-major gWorldViewProj
//   c12-c15 = row-major gViewInverse
//
// No D3D9 state is written by this probe.

static bool M3kP5cInvert4x4(const float* m, float* out) {
  double a[4][8] = {};
  for (int r = 0; r < 4; ++r) {
    for (int c = 0; c < 4; ++c)
      a[r][c] = static_cast<double>(m[r * 4 + c]);
    a[r][4 + r] = 1.0;
  }

  for (int c = 0; c < 4; ++c) {
    int pivot = c;
    double best = std::fabs(a[c][c]);
    for (int r = c + 1; r < 4; ++r) {
      const double v = std::fabs(a[r][c]);
      if (v > best) { best = v; pivot = r; }
    }
    if (best < 1.0e-10)
      return false;
    if (pivot != c)
      for (int k = 0; k < 8; ++k) {
        const double t = a[c][k]; a[c][k] = a[pivot][k]; a[pivot][k] = t;
      }

    const double div = a[c][c];
    for (int k = 0; k < 8; ++k) a[c][k] /= div;
    for (int r = 0; r < 4; ++r) {
      if (r == c) continue;
      const double f = a[r][c];
      if (std::fabs(f) < 1.0e-16) continue;
      for (int k = 0; k < 8; ++k) a[r][k] -= f * a[c][k];
    }
  }

  for (int r = 0; r < 4; ++r)
    for (int c = 0; c < 4; ++c)
      out[r * 4 + c] = static_cast<float>(a[r][4 + c]);
  return true;
}

static void M3kP5cMul4x4(const float* a, const float* b, float* out) {
  float tmp[16] = {};
  for (int r = 0; r < 4; ++r)
    for (int c = 0; c < 4; ++c) {
      double v = 0.0;
      for (int k = 0; k < 4; ++k)
        v += static_cast<double>(a[r * 4 + k]) * static_cast<double>(b[k * 4 + c]);
      tmp[r * 4 + c] = static_cast<float>(v);
    }
  std::memcpy(out, tmp, sizeof(tmp));
}

static bool M3kP5cAffineLike(const float* m) {
  return std::fabs(m[3]) < 0.02f && std::fabs(m[7]) < 0.02f &&
         std::fabs(m[11]) < 0.02f && std::fabs(m[15] - 1.0f) < 0.02f;
}

static bool M3kP5cProjective(const float* m) {
  const float wxyz = std::fabs(m[3]) + std::fabs(m[7]) + std::fabs(m[11]);
  return wxyz > 0.02f && std::fabs(m[15] - 1.0f) > 0.001f;
}

static ULONGLONG g_m3kP5cNextAttemptMs = 0;
static uint64_t g_m3kP5cSamples = 0;

static void M3kP5cCameraProbe(IDirect3DDevice9* device) {
  if (!device)
    return;

  const ULONGLONG now = GetTickCount64();
  if (now < g_m3kP5cNextAttemptMs)
    return;
  g_m3kP5cNextAttemptMs = now + 50; // at most 20 read-only state probes/second

  D3DVIEWPORT9 vp = {};
  if (FAILED(device->GetViewport(&vp)) || vp.Width < 320 || vp.Height < 180)
    return;

  float c[16 * 4] = {};
  if (FAILED(device->GetVertexShaderConstantF(0, c, 16)))
    return;

  const float* world = c + 0 * 4;
  const float* wvp = c + 8 * 4;
  const float* viewInv = c + 12 * 4;

  if (!M3kP5cProjective(wvp) ||
      !M3kP5cAffineLike(world) ||
      !M3kP5cAffineLike(viewInv))
    return;

  float worldInv[16] = {}, viewProj[16] = {}, proj[16] = {};
  if (!M3kP5cInvert4x4(world, worldInv))
    return;
  M3kP5cMul4x4(worldInv, wvp, viewProj);
  M3kP5cMul4x4(viewInv, viewProj, proj);

  const float px = proj[0], py = proj[5];
  const float A = proj[10], s = proj[11], B = proj[14], q = proj[15];

  if (!std::isfinite(px) || !std::isfinite(py) || !std::isfinite(A) ||
      !std::isfinite(s) || !std::isfinite(B) || !std::isfinite(q))
    return;
  if (std::fabs(px) < 0.05f || std::fabs(py) < 0.05f ||
      std::fabs(std::fabs(s) - 1.0f) > 0.08f || std::fabs(q) > 0.03f)
    return;

  // A normal D3D perspective matrix is sparse. Off-centre jitter lives in entries
  // we intentionally do not use for FOV/near/far, but a wildly non-projection
  // matrix is rejected here before it can become a calibration sample.
  const float structuralError =
      std::fabs(proj[1]) + std::fabs(proj[3]) +
      std::fabs(proj[4]) + std::fabs(proj[7]) +
      std::fabs(proj[12]) + std::fabs(proj[13]);
  if (structuralError > 0.12f)
    return;

  const float aspect = std::fabs(py / px);
  const float viewportAspect = static_cast<float>(vp.Width) / static_cast<float>(vp.Height);
  if (!std::isfinite(aspect) || std::fabs(aspect - viewportAspect) > viewportAspect * 0.10f)
    return;

  const float fovY = 2.0f * std::atan(1.0f / std::fabs(py));
  const float nearSigned = std::fabs(A) > 1.0e-7f ? (-B / A) : 0.0f;
  const float farDenom = s - A;
  const float farSigned = std::fabs(farDenom) > 1.0e-7f ? (B / farDenom) : 1.0e9f;

  float nearDist = std::fabs(nearSigned);
  float farDist = std::fabs(farSigned);
  bool reversedCandidate = false;
  if (nearDist > farDist && farDist > 1.0e-6f) {
    const float t = nearDist; nearDist = farDist; farDist = t;
    reversedCandidate = true;
  }

  if (!std::isfinite(fovY) || fovY < 0.20f || fovY > 2.80f ||
      !std::isfinite(nearDist) || nearDist < 0.0001f || nearDist > 100.0f ||
      !std::isfinite(farDist) || farDist < nearDist * 2.0f)
    return;

  ++g_m3kP5cSamples;
  Logger::info(format_string(
    "[M3K-CAMERA-P5C] sample=%llu viewport=%ux%u fovY=%.4fdeg near=%.6f far=%.3f "
    "aspect=%.5f depth=%s P22=%+.7f P23=%+.7f P32=%+.7f P33=%+.7f",
    static_cast<unsigned long long>(g_m3kP5cSamples),
    static_cast<unsigned>(vp.Width), static_cast<unsigned>(vp.Height),
    fovY * 57.29577951308232f, nearDist, farDist, aspect,
    reversedCandidate ? "REVERSED-CANDIDATE" : "NORMAL-CANDIDATE",
    A, s, B, q));
}

'''
text = text.replace(anchor, helpers + anchor, 1)

draw_markers = [
"""      case IDirect3DDevice9Ex_DrawPrimitive:
      {
        GET_RES(pD3DDevice, gpD3DDevices);
""",
"""      case IDirect3DDevice9Ex_DrawIndexedPrimitive:
      {
        GET_RES(pD3DDevice, gpD3DDevices);
""",
"""      case IDirect3DDevice9Ex_DrawPrimitiveUP:
      {
        GET_RES(pD3DDevice, gpD3DDevices);
""",
"""      case IDirect3DDevice9Ex_DrawIndexedPrimitiveUP:
      {
        GET_RES(pD3DDevice, gpD3DDevices);
"""
]
for marker in draw_markers:
    count = text.count(marker)
    if count != 1:
        raise SystemExit(f"draw marker count={count}, expected 1: {marker.splitlines()[0]}")
    text = text.replace(marker, marker + "        M3kP5cCameraProbe(pD3DDevice);\n", 1)

for marker in (
    "M3K-CAMERA-P5C",
    "Projection = ViewInverse * inverse(World) * WorldViewProjection",
    "GetVertexShaderConstantF(0, c, 16)",
    "M3kP5cCameraProbe(pD3DDevice);",
):
    if marker not in text:
        raise SystemExit(f"P5C verification marker missing: {marker}")

if text.count("M3kP5cCameraProbe(pD3DDevice);") != 4:
    raise SystemExit("P5C draw probe call count must be exactly 4")

source.write_text(text, encoding="utf-8", newline="\n")
print("Applied P5C server-only read-only GTA IV camera probe; 32-bit client remains untouched")
