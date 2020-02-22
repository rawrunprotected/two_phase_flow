#include "Definitions.h"

#include "SimulationConstants.hlsli"

#include "FFTWDefinitions.hlsli"

#define DECL Texture3D<float> I, out float O[N], uint2 is, uint2 os
#define IS(is, index) uint3(is, index)
#define OS(os, index) index

#include "e10_128.hlsli"

#undef DECL
#undef IS
#undef OS
#undef e00_129

#define DECL float I[N], RWTexture3D<float> O, uint2 is, uint2 os
#define IS(is, index) index
#define OS(os, index) uint3(os, index)

#include "e01_128.hlsli"

Texture3D<float> input : register(t0);
RWTexture3D<float> output : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
  float intermediate[N];

  e10_128(input, intermediate, dispatchThreadID.xy, dispatchThreadID.xy);

  [unroll]
  for (uint i = 0; i < N; ++i)
  {
    uint3 c = uint3(dispatchThreadID.xy, i);

    float3 cosines = cos(PI * c / N);
    const float dctNormalization = 8 * N * N * N;

    // Solve (1 - dt * dt * surfaceTension / eps * del) phiDiffused = phi
    intermediate[i] /= dctNormalization * (1 - 2 * (cosines.x + cosines.y + cosines.z - 3.0) * surfaceTension / levelSetDiffusion * dt * dt / (dx * dx));
  }

  e01_128(intermediate, output, dispatchThreadID.xy, dispatchThreadID.xy);
}