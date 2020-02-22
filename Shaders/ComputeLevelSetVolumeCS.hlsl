#include "Definitions.h"

#include "SimulationConstants.hlsli"

Texture3D<float> phi : register(t0);

#include "Volume.hlsli"

RWBuffer<float> volumeBuffer : register(u0);

[numthreads(SIZE_X, SIZE_Y, SIZE_Z)]
void main(int3 dispatchThreadID : SV_DispatchThreadID, uint groupIndex : SV_GroupIndex)
{
  float volume = computeLevelSetVolumeForOffset(0, dispatchThreadID, groupIndex);
  
  if (groupIndex == 0)
  {
    volumeBuffer[0] = volume;
  }
}