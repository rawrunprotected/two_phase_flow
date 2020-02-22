#include "Definitions.h"
#include "FFTWDefinitions.hlsli"
#include "SimulationConstants.hlsli"

#define DECL Texture3D<float> I, out float O[N + 1], uint2 is, uint2 os
#define IS(is, index) uint3(is, index)
#define OS(os, index) index
#define e00_129 e00_129_in

#include "e00_129.hlsli"

#undef DECL
#undef IS
#undef OS
#undef e00_129

#define DECL float I[N + 1], RWTexture3D<float> O, uint2 is, uint2 os
#define IS(is, index) index
#define OS(os, index) uint3(os, index)
#define e00_129 e00_129_out

#include "e00_129.hlsli"

Texture3D<float> input : register(t0);
RWTexture3D<float> output : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
  float intermediate[N + 1];

  e00_129_in(input, intermediate, dispatchThreadID.xy, dispatchThreadID.xy);

  [unroll]
  for (uint i = 0; i < N + 1; ++i)
  {
    uint3 c = uint3(dispatchThreadID.xy, i);
    if (all(c == 0))
    {
      // Set the coefficient at (0, 0, 0) to 0. This corresponds to the fact that the poisson equation
      // with periodic boundary conditions doesn't uniquely define the average value, so we just set it to an arbitrary value.
      intermediate[i] = 0;
    }
    else
    {
      // Divide by DFT of first order poisson stencil
      float3 cosines = cos(PI * c / N);
      float3 cosines2 = cos(2 * PI * c / N);
      const float dctNormalization = 8 * N * N * N;
      intermediate[i] /= dctNormalization * (-(cosines2.x + cosines2.y + cosines2.z) * 0.1666666666666 + (cosines.x + cosines.y + cosines.z) * 2.66666666666 - 7.5) / (dx * dx);
    }
  }

  e00_129_out(intermediate, output, dispatchThreadID.xy, dispatchThreadID.xy);
}