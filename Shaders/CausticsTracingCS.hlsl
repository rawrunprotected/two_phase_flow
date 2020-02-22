#include "Definitions.h"

#include "RenderConstants.hlsli"
#include "Caustics.hlsli"

SamplerState clampSampler : register(s0);
Texture3D<float> phi : register(t0);

RWTexture2D<uint> caustics : register(u0);

// On environment hit, intersect with ground plane and atomically add caustics to the map.
// By using R11G11B10 fixed point, we can use a single atomic R32 add, assuming there is no
// overflow between components.
void traceHitEnvironment(float3 rayStart, float3 rayDir, float3 attenuation)
{
  if (rayDir.z < 0 && any(attenuation > 0))
  {
    float2 groundHitPosition = rayStart.xy + rayDir.xy * (planeHeight - rayStart.z) / rayDir.z;

    int2 coord = (groundHitPosition / causticsRadius * 0.5 + 0.5) * CAUSTICS_RESOLUTION + 0.5;

    float cosAngle = -normalize(rayDir).z;
    
    uint _;
    InterlockedAdd(caustics[coord], encodeCaustics(attenuation * cosAngle), _);
  }
}

#include "Tracing.hlsli"

[numthreads(8, 8, 1)]
void main(int2 dispatchThreadID : SV_DispatchThreadID)
{
  float2 causticsPos = (float2(dispatchThreadID) / CAUSTICS_RESOLUTION * 2 - 1) * causticsRadius;

  float3 rayDirWorldSpace = normalize(float3(1, -2, -1));
  float3 rayStartWorldSpace = float3(causticsPos, planeHeight) - 10 * rayDirWorldSpace;

  traceScene(rayStartWorldSpace, rayDirWorldSpace);
}