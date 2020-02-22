#include "Definitions.h"

#include "SimulationConstants.hlsli"

Texture3D<float> u : register(t0);
Texture3D<float> v : register(t1);
Texture3D<float> w : register(t2);

RWTexture3D<float> div : register(u0);

[numthreads(4, 4, 4)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
  float divergence = 0;

  // Compute div(velocity) via 8-point staggered grid stencil.
  [unroll]
  for (int x = -1; x <= 1; x += 2)
  {
    [unroll]
    for (int y = -1; y <= 1; y += 2)
    {
      [unroll]
      for (int z = -1; z <= 1; z += 2)
      {
        int3 coord = dispatchThreadID + (int3(x, y, z) - 1) / 2;

        int3 clampedCoord = clamp(coord, 0, N - 1);

        float3 velocity = float3(u[clampedCoord], v[clampedCoord], w[clampedCoord]);

        // Use per-component odd mirrored boundary conditions to ensure velocities facing the box boundary
        // experience a virtual opposing velocity so that there is no flow through the box walls.
        velocity = (coord == clampedCoord) ? velocity : -velocity;
        
        divergence += dot(float3(x, y, z), velocity) * 0.25 / dx;
      }
    }
  }

  div[dispatchThreadID] = divergence;
}