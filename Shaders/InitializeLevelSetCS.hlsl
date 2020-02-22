#include "Definitions.h"

RWTexture3D<float> phi;

[numthreads(1, 1, 1)]
void main(int3 dispatchThreadID : SV_DispatchThreadID)
{
  // Demo scenarios for initial level set

  // Spherical drop from the ceiling
  // phi[dispatchThreadID] = -(length((dispatchThreadID - float3(N/2, N/2, N)) / float3(1, 1, 1)) - 50);

  // Density inversion - add some to assist symmetry breaking
  float noise = frac(dispatchThreadID.x * sqrt(2)) + frac(dispatchThreadID.y * sqrt(3));
  phi[dispatchThreadID] = float(dispatchThreadID.z - N / 2) + noise;
}