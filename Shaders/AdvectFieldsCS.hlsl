#include "Definitions.h"

#include "SimulationConstants.hlsli"

Texture3D<float> u : register(t0);
Texture3D<float> v : register(t1);
Texture3D<float> w : register(t2);
Texture3D<float> phiIn : register(t3);

RWTexture3D<float> uOut : register(u0);
RWTexture3D<float> vOut : register(u1);
RWTexture3D<float> wOut : register(u2);
RWTexture3D<float> phiOut : register(u3);

SamplerState s : register(s0);

[numthreads(4, 4, 4)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
  // Semi-Lagrangian advection scheme.

  float3 velocity = float3(u[dispatchThreadID], v[dispatchThreadID], w[dispatchThreadID]);

  float3 sourceCoord = (dispatchThreadID + 0.5) / N;

  float3 advectedCoord = sourceCoord - dt * velocity / (N * dx);

  uOut[dispatchThreadID] = u.SampleLevel(s, advectedCoord, 0);
  vOut[dispatchThreadID] = v.SampleLevel(s, advectedCoord, 0);
  wOut[dispatchThreadID] = w.SampleLevel(s, advectedCoord, 0);
  phiOut[dispatchThreadID] = phiIn.SampleLevel(s, advectedCoord, 0);
}