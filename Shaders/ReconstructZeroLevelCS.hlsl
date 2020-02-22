#include "Definitions.h"

#include "SimulationConstants.hlsli"

Texture3D<float> phiIn : register(t0);

RWTexture3D<float> phiOut : register(u0);

[numthreads(4, 4, 4)]
void main(int3 dispatchThreadID : SV_DispatchThreadID)
{
  // Reconstruct zero level set as per Sethian, Level Set Methods and Fast Marching Methods, 11.4.1 - Constructing Signed Distances
  float phi0 = phiIn[dispatchThreadID];

  float phiPx = phiIn[clamp(dispatchThreadID + int3(+1, 0, 0), 0, N - 1)];
  float phiNx = phiIn[clamp(dispatchThreadID + int3(-1, 0, 0), 0, N - 1)];

  float phiPy = phiIn[clamp(dispatchThreadID + int3(0, +1, 0), 0, N - 1)];
  float phiNy = phiIn[clamp(dispatchThreadID + int3(0, -1, 0), 0, N - 1)];

  float phiPz = phiIn[clamp(dispatchThreadID + int3(0, 0, +1), 0, N - 1)];
  float phiNz = phiIn[clamp(dispatchThreadID + int3(0, 0, -1), 0, N - 1)];

  // Compute distances to level set intersection point along each axis
  float distPx = sign(phi0) != sign(phiPx) ? abs(phi0 / (phiPx - phi0)) : 1e9f;
  float distNx = sign(phi0) != sign(phiNx) ? abs(phi0 / (phiNx - phi0)) : 1e9f;
  float distPy = sign(phi0) != sign(phiPy) ? abs(phi0 / (phiPy - phi0)) : 1e9f;
  float distNy = sign(phi0) != sign(phiNy) ? abs(phi0 / (phiNy - phi0)) : 1e9f;
  float distPz = sign(phi0) != sign(phiPz) ? abs(phi0 / (phiPz - phi0)) : 1e9f;
  float distNz = sign(phi0) != sign(phiNz) ? abs(phi0 / (phiNz - phi0)) : 1e9f;

  float distX = min(distPx, distNx);
  float distY = min(distPy, distNy);
  float distZ = min(distPz, distNz);

  // Recompute distance to the level set. For cells without adjacent cells of the opposite sign
  // this will assign a value of sign(phi) * 1e9f, which will then be corrected by later jump flooding passes.
  phiOut[dispatchThreadID] = dx * sign(phi0) * rsqrt(rcp(distX * distX) + rcp(distY * distY) + rcp(distZ * distZ));
}