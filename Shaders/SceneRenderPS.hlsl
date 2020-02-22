#include "Definitions.h"

#include "RenderConstants.hlsli"

SamplerState clampSampler : register(s0);
Texture3D<float> phi : register(t0);

TextureCube<float3> skyBox : register(t1);

Texture2D<float3> caustics : register(t2);

static float3 g_accumulatedColor = float3(0, 0, 0);
void traceHitEnvironment(float3 rayStart, float3 rayDir, float3 attenuation)
{
  if (rayDir.z < 0)
  {
    float2 groundHitPosition = rayStart.xy + rayDir.xy * (planeHeight - rayStart.z) / rayDir.z;

    float2 coord = groundHitPosition / causticsRadius * 0.5 + 0.5;

    // If we hit the ground plane, sample caustics.
    if (all(coord == saturate(coord)))
    {
      uint2 checkerBoard = coord * 16;
      float3 checkerBoardColor = float3(0.05, 0.05, 0.05) + ((checkerBoard.x ^ checkerBoard.y) & 1) * float3(0.15, 0.15, 0.15);
      g_accumulatedColor += (caustics.Sample(clampSampler, coord) + checkerBoardColor) * attenuation;
      return;
    }
  }
  
  g_accumulatedColor += skyBox.SampleLevel(clampSampler, rayDir.xzy, 0) * attenuation;
}

#include "Tracing.hlsli"

float4 main(float2 UV : TEXCOORD) : SV_TARGET
{
  float4 clipSpaceRayStart = float4(UV * 2 - 1, -1, 1);
  float4 clipSpaceRayEnd = float4(UV * 2 - 1, 1, 1);

  clipSpaceRayStart.y *= -1;
  clipSpaceRayEnd.y *= -1;

  float3 rayStartWorldSpace = mul(worldFromProj, clipSpaceRayStart).xyz / mul(worldFromProj, clipSpaceRayStart).w;
  float3 rayEndWorldSpace = mul(worldFromProj, clipSpaceRayEnd).xyz / mul(worldFromProj, clipSpaceRayEnd).w;

  // Trace along view ray and accumulate light along rays.
  traceScene(rayStartWorldSpace, rayEndWorldSpace);

  return float4(g_accumulatedColor, 1);
}