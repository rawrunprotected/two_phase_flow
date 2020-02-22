#define SIZE_X 16
#define SIZE_Y 8
#define SIZE_Z 8

#define GROUP_SIZE SIZE_X * SIZE_Y * SIZE_Z

groupshared float sdata[GROUP_SIZE];

float computeLevelSetVolumeForOffset(float offset, int3 dispatchThreadID, uint groupIndex)
{
  float localVolumeSum = 0.0;

  for (uint x = dispatchThreadID.x; x < N; x += SIZE_X)
  {
    for (uint y = dispatchThreadID.y; y < N; y += SIZE_Y)
    {
      for (uint z = dispatchThreadID.z; z < N; z += SIZE_Z)
      {
        localVolumeSum += Heavyside((phi[uint3(x, y, z)] + offset) / interfaceWidth) * dx * dx * dx;
      }
    }
  }

  GroupMemoryBarrierWithGroupSync();

  sdata[groupIndex] = localVolumeSum;

  GroupMemoryBarrierWithGroupSync();

  for (unsigned int s = GROUP_SIZE / 2; s > 0; s >>= 1)
  {
    if (groupIndex < s)
    {
      sdata[groupIndex] += sdata[groupIndex + s];
    }
    GroupMemoryBarrierWithGroupSync();
  }

  return sdata[0];
}