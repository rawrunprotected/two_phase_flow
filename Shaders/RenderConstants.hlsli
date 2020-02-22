cbuffer RenderConstants : register(b0)
{
  float4x4 projFromWorld;
  float4x4 worldFromProj;

  float refractionIndexPhase0;
  float refractionIndexPhase1;

  float causticsRadius;
  float planeHeight;
}
