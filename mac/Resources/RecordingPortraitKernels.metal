#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

extern "C" {
    float4 portraitMask(float4 region, float amount, coreimage::destination destination) {
        float2 relative = (destination.coord() - region.xy) / region.zw;
        float weight = amount * (1.0 - smoothstep(0.7, 1.0, length(relative)));
        return float4(float3(weight), 1.0);
    }

    float2 portraitSlim(float4 region, float amount, coreimage::destination destination) {
        float2 point = destination.coord();
        float2 relative = (point - region.xy) / region.zw;
        float weight = max(0.0, 1.0 - dot(relative, relative));
        return point + float2((point.x - region.x) * amount * weight * weight, 0.0);
    }
}
