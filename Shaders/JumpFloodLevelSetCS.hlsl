#include "Definitions.h"

#include "SimulationConstants.hlsli"

Texture3D<float> phiIn : register(t0);

RWTexture3D<float> phiOut : register(u0);

[numthreads(4, 4, 4)]
void main(int3 dispatchThreadID : SV_DispatchThreadID)
{
  // Simplified jump flooding

  float phi = phiIn[dispatchThreadID];

  [unroll]
  for (int x = -1; x <= 1; x += 1)
  {
    [unroll]
    for (int y = -1; y <= 1; y += 1)
    {
      [unroll]
      for (int z = -1; z <= 1; z += 1)
      {
        if (x == 0 && y == 0 && z == 0)
        {
          continue;
        }

        int3 jump = int3(x, y, z) * stepSize;

        float phiN = phiIn[clamp(dispatchThreadID + jump, 0, N - 1)];
        if (sign(phiN) == sign(phi))
        {
          phi = sign(phi) * min(abs(phi), abs(phiN) + dx * stepSize * length(float3(x, y, z)));
        }
      }
    }
  }

  phiOut[dispatchThreadID] = phi;
}