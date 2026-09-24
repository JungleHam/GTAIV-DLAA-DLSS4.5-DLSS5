#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: Public-BBridge-Camera-Probe.py <b-bridge-root>")

root = Path(sys.argv[1])
device = root / "src" / "client" / "d3d9_device.cpp"
if not device.is_file():
    raise SystemExit(f"missing b-bridge source: {device}")

text = device.read_text(encoding="utf-8")
if "M3K-CAMERA-P5" in text:
    print("P5 camera probe already present")
    raise SystemExit(0)

anchor = """static bool M3kBuildDrawWvp(const M3kJitterConfig& config,
"""
at = text.find(anchor)
if at < 0:
    raise SystemExit("M3kBuildDrawWvp anchor missing")

helpers = r'''
// M3K-CAMERA-P5: read-only projection telemetry.
//
// GTA IV PC shader metadata identifies common world-shader constants as:
//   c0-c3   = row-major gWorld
//   c8-c11  = row-major gWorldViewProj
//   c12-c15 = row-major gViewInverse
//
// The production jitter path already reads c8-c11. This probe only reads the two
// neighbouring matrices and derives Projection = ViewInverse * inverse(World) * WVP.
// It never changes a constant, draw, viewport, phase, or Present ordering.

static bool M3kCameraInvert4x4(const float* m, float* out) {
  double a[4][8] = {};
  for (int r = 0; r < 4; ++r) {
    for (int c = 0; c < 4; ++c)
      a[r][c] = static_cast<double>(m[r * 4 + c]);
    a[r][4 + r] = 1.0;
  }

  for (int c = 0; c < 4; ++c) {
    int pivot = c;
    double best = fabs(a[c][c]);
    for (int r = c + 1; r < 4; ++r) {
      const double v = fabs(a[r][c]);
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
      if (fabs(f) < 1.0e-16) continue;
      for (int k = 0; k < 8; ++k) a[r][k] -= f * a[c][k];
    }
  }

  for (int r = 0; r < 4; ++r)
    for (int c = 0; c < 4; ++c)
      out[r * 4 + c] = static_cast<float>(a[r][4 + c]);
  return true;
}

static void M3kCameraMul4x4(const float* a, const float* b, float* out) {
  float tmp[16] = {};
  for (int r = 0; r < 4; ++r)
    for (int c = 0; c < 4; ++c) {
      double v = 0.0;
      for (int k = 0; k < 4; ++k)
        v += static_cast<double>(a[r * 4 + k]) * static_cast<double>(b[k * 4 + c]);
      tmp[r * 4 + c] = static_cast<float>(v);
    }
  memcpy(out, tmp, sizeof(tmp));
}

static bool M3kCameraAffineLike(const float* m) {
  return fabsf(m[3]) < 0.02f && fabsf(m[7]) < 0.02f &&
         fabsf(m[11]) < 0.02f && fabsf(m[15] - 1.0f) < 0.02f;
}

static ULONGLONG g_m3kCameraNextProbeMs = 0;
static uint64_t g_m3kCameraAccepted = 0;

static void M3kCameraProbeTry(const float* world, const float* wvp, const float* viewInv,
                              UINT viewportWidth, UINT viewportHeight, uint32_t shaderId) {
  const ULONGLONG now = GetTickCount64();
  if (now < g_m3kCameraNextProbeMs)
    return;
  g_m3kCameraNextProbeMs = now + 250;

  if (!viewportWidth || !viewportHeight ||
      !M3kWvpProjective(wvp) ||
      !M3kCameraAffineLike(world) || !M3kCameraAffineLike(viewInv))
    return;

  float worldInv[16] = {}, viewProj[16] = {}, proj[16] = {};
  if (!M3kCameraInvert4x4(world, worldInv))
    return;
  M3kCameraMul4x4(worldInv, wvp, viewProj);
  M3kCameraMul4x4(viewInv, viewProj, proj);

  const float px = proj[0], py = proj[5];
  const float A = proj[10], s = proj[11], B = proj[14], q = proj[15];
  if (!std::isfinite(px) || !std::isfinite(py) || !std::isfinite(A) ||
      !std::isfinite(s) || !std::isfinite(B) || !std::isfinite(q))
    return;
  if (fabsf(px) < 0.05f || fabsf(py) < 0.05f ||
      fabsf(fabsf(s) - 1.0f) > 0.08f || fabsf(q) > 0.03f)
    return;

  // Perspective matrices can have off-centre terms in row 2, but these entries
  // should remain near zero for a normal D3D projection.
  const float structuralError =
      fabsf(proj[1]) + fabsf(proj[2]) + fabsf(proj[3]) +
      fabsf(proj[4]) + fabsf(proj[6]) + fabsf(proj[7]) +
      fabsf(proj[12]) + fabsf(proj[13]);
  if (structuralError > 0.12f)
    return;

  const float aspect = fabsf(py / px);
  const float viewportAspect = static_cast<float>(viewportWidth) / static_cast<float>(viewportHeight);
  if (!std::isfinite(aspect) || fabsf(aspect - viewportAspect) > viewportAspect * 0.08f)
    return;

  const float fovY = 2.0f * atanf(1.0f / fabsf(py));
  const float nearSigned = fabsf(A) > 1.0e-7f ? (-B / A) : 0.0f;
  const float farDenom = s - A;
  float farSigned = fabsf(farDenom) > 1.0e-7f ? (B / farDenom) : 1.0e9f;
  float nearDist = fabsf(nearSigned);
  float farDist = fabsf(farSigned);
  bool reversed = false;
  if (nearDist > farDist && farDist > 1.0e-6f) {
    const float t = nearDist; nearDist = farDist; farDist = t;
    reversed = true;
  }

  if (!std::isfinite(fovY) || fovY < 0.20f || fovY > 2.80f ||
      !std::isfinite(nearDist) || nearDist < 0.0001f || nearDist > 100.0f ||
      !std::isfinite(farDist) || farDist < nearDist * 2.0f)
    return;

  ++g_m3kCameraAccepted;
  Logger::info(format_string(
    "[M3K-CAMERA-P5] sample=%llu shader=%u viewport=%ux%u fovY=%.4fdeg near=%.6f far=%.3f "
    "aspect=%.5f depth=%s P22=%+.7f P23=%+.7f P32=%+.7f P33=%+.7f",
    static_cast<unsigned long long>(g_m3kCameraAccepted), shaderId,
    viewportWidth, viewportHeight, fovY * 57.29577951308232f,
    nearDist, farDist, aspect, reversed ? "REVERSED-CANDIDATE" : "NORMAL-CANDIDATE",
    A, s, B, q));
}

'''
text = text[:at] + helpers + text[at:]

old_arrays = """    float m3kOriginalWvp[16] = { }; \\
    UINT m3kViewportW = 0, m3kViewportH = 0; \\
"""
new_arrays = """    float m3kOriginalWvp[16] = { }; \\
    float m3kCameraWorld[16] = { }; \\
    float m3kCameraViewInv[16] = { }; \\
    UINT m3kViewportW = 0, m3kViewportH = 0; \\
"""
if text.count(old_arrays) != 1:
    raise SystemExit(f"draw local-array anchor count={text.count(old_arrays)}, expected 1")
text = text.replace(old_arrays, new_arrays, 1)

old_copy = """      for (UINT m3kR = 0; m3kR < 4u; ++m3kR) \\
        for (UINT m3kC = 0; m3kC < 4u; ++m3kC) \\
          m3kOriginalWvp[m3kR * 4u + m3kC] = m_state.vertexConstants.fConsts[8u + m3kR].data[m3kC]; \\
"""
new_copy = """      for (UINT m3kR = 0; m3kR < 4u; ++m3kR) \\
        for (UINT m3kC = 0; m3kC < 4u; ++m3kC) { \\
          m3kCameraWorld[m3kR * 4u + m3kC] = m_state.vertexConstants.fConsts[0u + m3kR].data[m3kC]; \\
          m3kOriginalWvp[m3kR * 4u + m3kC] = m_state.vertexConstants.fConsts[8u + m3kR].data[m3kC]; \\
          m3kCameraViewInv[m3kR * 4u + m3kC] = m_state.vertexConstants.fConsts[12u + m3kR].data[m3kC]; \\
        } \\
"""
if text.count(old_copy) != 1:
    raise SystemExit(f"matrix capture anchor count={text.count(old_copy)}, expected 1")
text = text.replace(old_copy, new_copy, 1)

old_after_lock = """    } \\
    if (!m3kRecording) { \\
      float m3kDesiredWvp[16] = { }; \\
"""
new_after_lock = """    } \\
    if (!m3kRecording) { \\
      M3kCameraProbeTry(m3kCameraWorld, m3kOriginalWvp, m3kCameraViewInv, \\
                        m3kViewportW, m3kViewportH, m3kShaderId); \\
      float m3kDesiredWvp[16] = { }; \\
"""
if text.count(old_after_lock) != 1:
    raise SystemExit(f"probe-call insertion anchor count={text.count(old_after_lock)}, expected 1")
text = text.replace(old_after_lock, new_after_lock, 1)

for marker in (
    "M3K-CAMERA-P5",
    "M3kCameraProbeTry",
    "m3kCameraWorld",
    "m3kCameraViewInv",
    "Projection = ViewInverse * inverse(World) * WVP",
):
    if marker not in text:
        raise SystemExit(f"camera probe verification marker missing: {marker}")

device.write_text(text, encoding="utf-8", newline="\n")
print("Applied P5 read-only GTA IV camera projection probe; render/jitter behavior unchanged")
