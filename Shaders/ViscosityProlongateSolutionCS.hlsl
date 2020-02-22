Texture3D<float> inputU : register(t0);
Texture3D<float> inputV : register(t1);
Texture3D<float> inputW : register(t2);

RWTexture3D<float> outputU : register(u0);
RWTexture3D<float> outputV : register(u1);
RWTexture3D<float> outputW : register(u2);

SamplerState s : register(s0);

[numthreads(4, 4, 4)]
void main(int3 dispatchThreadID : SV_DispatchThreadID)
{
  // Upscale viscosity solution from a lower to a higher grid level.
  float w, h, d;
  outputU.GetDimensions(w, h, d);

  float3 coord = (dispatchThreadID + 0.5) / float3(w, h, d);
  outputU[dispatchThreadID] += inputU.SampleLevel(s, coord, 0);
  outputV[dispatchThreadID] += inputV.SampleLevel(s, coord, 0);
  outputW[dispatchThreadID] += inputW.SampleLevel(s, coord, 0);
}