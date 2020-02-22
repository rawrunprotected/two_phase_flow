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
  float residualU = 0.0;
  float residualV = 0.0;
  float residualW = 0.0;

  // Compute cell residuals and average to compute lower grid viscosity residual restriction.
  // We rely on out-of-bound loads returning 0 here, causing fluid to experience high friction
  // at the box walls.
  [unroll]
  for (int x = 0; x <= 1; ++x)
  {
    [unroll]
    for (int y = 0; y <= 1; ++y)
    {
      [unroll]
      for (int z = 0; z <= 1; ++z)
      {
        int3 coord = dispatchThreadID * 2;

        float c = dt * viscosity / (dx * dx);

        float sumU =
          inputU[coord + int3(x - 1, y, z)] +
          inputU[coord + int3(x + 1, y, z)] +
          inputU[coord + int3(x, y - 1, z)] +
          inputU[coord + int3(x, y + 1, z)] +
          inputU[coord + int3(x, y, z - 1)] +
          inputU[coord + int3(x, y, z + 1)];

        float centerU = inputU[coord + int3(x, y, z)];
        residualU += rhsU[coord + int3(x, y, z)] - centerU + c * (sumU - 6 * centerU);

        float sumV =
          inputV[coord + int3(x - 1, y, z)] +
          inputV[coord + int3(x + 1, y, z)] +
          inputV[coord + int3(x, y - 1, z)] +
          inputV[coord + int3(x, y + 1, z)] +
          inputV[coord + int3(x, y, z - 1)] +
          inputV[coord + int3(x, y, z + 1)];

        float centerV = inputV[coord + int3(x, y, z)];
        residualV += rhsV[coord + int3(x, y, z)] - centerV + c * (sumV - 6 * centerV);

        float sumW =
          inputW[coord + int3(x - 1, y, z)] +
          inputW[coord + int3(x + 1, y, z)] +
          inputW[coord + int3(x, y - 1, z)] +
          inputW[coord + int3(x, y + 1, z)] +
          inputW[coord + int3(x, y, z - 1)] +
          inputW[coord + int3(x, y, z + 1)];

        float centerW = inputW[coord + int3(x, y, z)];
        residualW += rhsW[coord + int3(x, y, z)] - centerW + c * (sumW - 6 * centerW);
      }
    }
  }

  outputU[dispatchThreadID] = residualU / 8;
  outputV[dispatchThreadID] = residualV / 8;
  outputW[dispatchThreadID] = residualW / 8;
}