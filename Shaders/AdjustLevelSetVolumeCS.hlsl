#include "Definitions.h"

#include "SimulationConstants.hlsli"

RWTexture3D<float> phi : register(u0);

#include "Volume.hlsli"

Buffer<float> volumeBuffer : register(t0);

void applyOffset(float offset, int3 dispatchThreadID, uint groupIndex)
{
  float localVolumeSum = 0.0;

  for (uint x = dispatchThreadID.x; x < N; x += SIZE_X)
  {
    for (uint y = dispatchThreadID.y; y < N; y += SIZE_Y)
    {
      for (uint z = dispatchThreadID.z; z < N; z += SIZE_Z)
      {
        phi[uint3(x, y, z)] += offset;
      }
    }
  }
}

[numthreads(SIZE_X, SIZE_Y, SIZE_Z)]
void main(int3 dispatchThreadID : SV_DispatchThreadID, uint groupIndex : SV_GroupIndex)
{
  float targetVolume = volumeBuffer[0];

  // Shift level set by up to 1/2 cell distance to recover lost volume.
  // Search for optimal offset via regula falsi.
  float a = -0.5 * dx;
  float b = 0.5 * dx;

  float fa = computeLevelSetVolumeForOffset(a, dispatchThreadID, groupIndex) - targetVolume;
  float fb = computeLevelSetVolumeForOffset(b, dispatchThreadID, groupIndex) - targetVolume;
  for (uint i = 0; i < 10; ++i)
  {
    if (sign(fa) == sign(fb))
    {
      break;
    }

    float c = (fa * b - fb * a) / (fa - fb);
    float fc = computeLevelSetVolumeForOffset(c, dispatchThreadID, groupIndex) - targetVolume;

    if (sign(fc) == sign(fb))
    {
      b = c;
      fb = fc;
    }
    else
    {
      a = c;
      fa = fc;
    }
  }

  applyOffset(abs(fa) < abs(fb) ? a : b, dispatchThreadID, groupIndex);
}