#include "ReShade.fxh"

uniform float M3K_Sharpness <
    ui_type = "drag";
    ui_label = "M3K Sharpness";
    ui_min = 0.0;
    ui_max = 1.0;
    ui_step = 0.01;
> = 0.0;

float4 M3K_SharpenPS(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    const float2 px = ReShade::PixelSize;
    const float4 center = tex2D(ReShade::BackBuffer, texcoord);

    const float3 left  = tex2D(ReShade::BackBuffer, texcoord + float2(-px.x, 0.0)).rgb;
    const float3 right = tex2D(ReShade::BackBuffer, texcoord + float2( px.x, 0.0)).rgb;
    const float3 up    = tex2D(ReShade::BackBuffer, texcoord + float2(0.0, -px.y)).rgb;
    const float3 down  = tex2D(ReShade::BackBuffer, texcoord + float2(0.0,  px.y)).rgb;

    // Small, stable post-reconstruction unsharp pass.
    // 0.0 is a byte-for-behaviour visual bypass; 1.0 is intentionally moderate.
    const float3 localAverage = (left + right + up + down) * 0.25;
    const float3 detail = center.rgb - localAverage;
    const float3 sharpened = center.rgb + detail * M3K_Sharpness;

    return float4(saturate(sharpened), center.a);
}

technique M3K_Sharpen
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = M3K_SharpenPS;
    }
}
