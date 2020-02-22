#include "Definitions.h"

#include "SimulationConstants.hlsli"

RWTexture3D<float> u : register(u0);
RWTexture3D<float> v : register(u1);
RWTexture3D<float> w : register(u2);

Texture3D<float> p : register(t0);

[numthreads(4, 4, 4)]
void main(int3 dispatchThreadID : SV_DispatchThreadID)
{
  float3 gradient = 0;

  // Compute pressure gradient as staggered 8-point stencil
  [unroll]
  for (int x = -1; x <= 1; x += 2)
  {
    [unroll]
    for (int y = -1; y <= 1; y += 2)
    {
      [unroll]
      for (int z = -1; z <= 1; z += 2)
      {
        int3 coord = dispatchThreadID + (int3(x, y, z) + 1) / 2;
        gradient += 0.25 * float3(x, y, z) * p[coord] / dx;
      }
    }
  }

  u[dispatchThreadID] -= gradient.x;
  v[dispatchThreadID] -= gradient.y;
  w[dispatchThreadID] -= gradient.z;
}