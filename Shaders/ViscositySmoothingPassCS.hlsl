#include "SimulationConstants.hlsli"

Texture3D<float> inputU : register(t0);
Texture3D<float> inputV : register(t1);
Texture3D<float> inputW : register(t2);

Texture3D<float> rhsU : register(t3);
Texture3D<float> rhsV : register(t4);
Texture3D<float> rhsW : register(t5);

RWTexture3D<float> outputU : register(u0);
RWTexture3D<float> outputV : register(u1);
RWTexture3D<float> outputW : register(u2);

[numthreads(4, 4, 4)]
void main(int3 dispatchThreadID : SV_DispatchThreadID)
{
  // Viscosity solver smoothing pass.
  float c = dt * viscosity / (dx * dx);

  float sumU =
    inputU[dispatchThreadID + int3(-1, 0, 0)] +
    inputU[dispatchThreadID + int3(+1, 0, 0)] +
    inputU[dispatchThreadID + int3(0, -1, 0)] +
    inputU[dispatchThreadID + int3(0, +1, 0)] +
    inputU[dispatchThreadID + int3(0, 0, -1)] +
    inputU[dispatchThreadID + int3(0, 0, +1)];

  outputU[dispatchThreadID] = (rhsU[dispatchThreadID] + sumU * c) / (1 + 6 * c);

  float sumV =
    inputV[dispatchThreadID + int3(-1, 0, 0)] +
    inputV[dispatchThreadID + int3(+1, 0, 0)] +
    inputV[dispatchThreadID + int3(0, -1, 0)] +
    inputV[dispatchThreadID + int3(0, +1, 0)] +
    inputV[dispatchThreadID + int3(0, 0, -1)] +
    inputV[dispatchThreadID + int3(0, 0, +1)];

  outputV[dispatchThreadID] = (rhsV[dispatchThreadID] + sumV * c) / (1 + 6 * c);

  float sumW =
    inputW[dispatchThreadID + int3(-1, 0, 0)] +
    inputW[dispatchThreadID + int3(+1, 0, 0)] +
    inputW[dispatchThreadID + int3(0, -1, 0)] +
    inputW[dispatchThreadID + int3(0, +1, 0)] +
    inputW[dispatchThreadID + int3(0, 0, -1)] +
    inputW[dispatchThreadID + int3(0, 0, +1)];

  outputW[dispatchThreadID] = (rhsW[dispatchThreadID] + sumW * c) / (1 + 6 * c);
}