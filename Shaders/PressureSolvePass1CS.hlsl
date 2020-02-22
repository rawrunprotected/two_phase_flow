#include "FFTWDefinitions.hlsli"

#define DECL Texture3D<float> I, RWTexture3D<float> O, uint2 is, uint2 os
#define IS(is, index) uint3(index, is)
#define OS(os, index) uint3(index, os)

#include "e00_129.hlsli"

Texture3D<float> input : register(t0);
RWTexture3D<float> output : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
  e00_129(input, output, dispatchThreadID.xy, dispatchThreadID.xy);
}