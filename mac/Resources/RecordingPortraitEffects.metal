#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

extern "C" {
namespace coreimage {
    float4 portraitMask(float4 region, float amount, destination dest) {
        float2 relative = (dest.coord() - region.xy) / region.zw;
        float weight = amount * (1.0 - smoothstep(0.7, 1.0, length(relative)));
        return float4(float3(weight), 1.0);
    }

    float2 portraitSlim(float4 region, float amount, destination dest) {
        float2 point = dest.coord();
        float2 relative = (point - region.xy) / region.zw;
        float weight = max(0.0, 1.0 - dot(relative, relative));
        return point + float2((point.x - region.x) * amount * weight * weight, 0.0);
    }
}
}
