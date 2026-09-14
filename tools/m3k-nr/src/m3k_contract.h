// SPDX-License-Identifier: Apache-2.0
// M3K adaptation of the feature-18 contract from DLSS5 ReShade AIO.
// Copyright 2026 kibblerz. Modifications Copyright 2026 JungleHam.
// Reference: 09301f5528e619e8b9ec17c257d167e2985f53b0; see ../NOTICE.
#pragma once
#include <cstdio>
#include <initializer_list>

namespace m3k {
constexpr int FeatureId = 18;
constexpr unsigned long long SnippetAppId = 0x876232CULL;

// Templates keep the private parameter ABI independently testable. The real
// instantiation uses Feeder's SDK NVSDK_NGX_Parameter, never a replacement vtable.
template<class P> void CreateContract(P *p, unsigned w, unsigned h, int flags)
{
    p->Set("CreationNodeMask", 1u); p->Set("VisibilityNodeMask", 1u);
    for (const char *key : {"Width", "OutWidth", "ResourceWidth", "ResourceOutWidth",
         "DLSSNR.InputWidth", "DLSSNR.Width", "DLSSNR.OutputWidth", "Output.Width"}) p->Set(key, w);
    for (const char *key : {"Height", "OutHeight", "ResourceHeight", "ResourceOutHeight",
         "DLSSNR.InputHeight", "DLSSNR.Height", "DLSSNR.OutputHeight", "Output.Height"}) p->Set(key, h);
    p->Set("PerfQualityValue", 5); // NVSDK_NGX_PerfQuality_Value_DLAA
    p->Set("DLSS.Feature.Create.Flags", flags);
    p->Set("DLSS.Enable.Output.Subrects", 0);
    p->Set("DLSS.Denoise.Mode", 1); p->Set("DLSS.Roughness.Mode", 0u);
    p->Set("DLSS.Use.HW.Depth", 1u);
    p->Set("DLSSNR.Enabled", 1u);
    // Private provider switch, NOT a request to enlarge the image. AIO uses 1
    // even for 1:1. All dimensions and ratios above/below remain native.
    p->Set("DLSSNR.Upscaling", 1u);
    p->Set("DLSSNR.ScalingRatio", 1.0f); p->Set("DLSSNR.Scale", 1.0f);
    p->Set("DLSSNR.Hint.Render.Preset", 1);
    p->Set("DLSSNR.Style", 0u);
    for (const char *key : {"DLSSNR.Intensity", "DLSSNR.LocalToneStrength",
         "DLSSNR.LocalStructureStrength", "DLSSNR.SkinStructureStrength"}) p->Set(key, 1.0f);
    p->Set("DLSSNR.UseAutoMask", 1u); // provider's internal mask, no supplied UI mask
    p->Set("DLSSNR.UICorrection", 0u);
}

template<class P, class R> void EvalContract(P *p, R *color, R *output, R *depth, R *mv,
    unsigned w, unsigned h, bool reset, bool reversed, float jx, float jy, float mx, float my,
    float preExposure, float exposure)
{
    p->Set("Color", color); p->Set("DLSSNR.Color", color);
    p->Set("Output", output); p->Set("DLSSNR.Output", output);
    p->Set("Depth", depth); p->Set("DLSSNR.Depth", depth);
    p->Set("MotionVectors", mv); p->Set("DLSSNR.MVec", mv);
    p->Set("Reset", int(reset)); p->Set("DLSSNR.Reset", int(reset));
    p->Set("Jitter.Offset.X", jx); p->Set("DLSSNR.JitterOffsetX", jx);
    p->Set("Jitter.Offset.Y", jy); p->Set("DLSSNR.JitterOffsetY", jy);
    p->Set("MV.Scale.X", mx); p->Set("DLSSNR.MVecScaleX", mx);
    p->Set("MV.Scale.Y", my); p->Set("DLSSNR.MVecScaleY", my);
    p->Set("DLSS.Pre.Exposure", preExposure); p->Set("DLSS.Exposure.Scale", exposure);
    p->Set("DLSS.Render.Subrect.Dimensions.Width", w);
    p->Set("DLSS.Render.Subrect.Dimensions.Height", h);
    p->Set("DLSSNR.DepthInverted", unsigned(reversed));
    // The private subrect values are I32, unlike the public U32 DLSS keys.
    for (const char *resource : {"Color", "Output", "Depth", "MVec"}) {
        char key[80];
        sprintf_s(key, "DLSSNR.%sSubrectBaseX", resource); p->Set(key, 0);
        sprintf_s(key, "DLSSNR.%sSubrectBaseY", resource); p->Set(key, 0);
        sprintf_s(key, "DLSSNR.%sSubrectWidth", resource); p->Set(key, int(w));
        sprintf_s(key, "DLSSNR.%sSubrectHeight", resource); p->Set(key, int(h));
    }
    for (const char *key : {"DLSSNR.ControlMask", "DLSSNR.UI", "DLSSNR.UIAlpha",
         "DLSSNR.Backbuffer", "DLSSNR.BidirectionalDistortionField"}) p->Set(key, static_cast<R *>(nullptr));
}
} // namespace m3k
