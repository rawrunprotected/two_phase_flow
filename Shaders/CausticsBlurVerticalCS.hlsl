#include "Definitions.h"

Texture2D<float3> input : register(t0);
RWTexture2D<float3> output : register(u0);

[numthreads(8, 8, 1)]
void main(uint2 dispatchThreadID : SV_DispatchThreadID)
{
	// Caustics vertical blur
	int dx = ceil(2 * CAUSTICS_BLUR_SIGMA);

	float3 total = 0;
	float weightSum = 0;

	[unroll]
	for (int i = -dx; i <= dx; i++)
	{
		float3 value = input.Load(int3(dispatchThreadID, 0), int2(0, i));
		float weight = exp(-0.5 * i * i / (CAUSTICS_BLUR_SIGMA * CAUSTICS_BLUR_SIGMA));
		total += weight * value;
		weightSum += weight;
	}

	output[dispatchThreadID] = total / weightSum;
}