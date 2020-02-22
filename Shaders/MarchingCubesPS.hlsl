struct GS_OUTPUT
{
  float4 position : SV_Position;
  float3 worldpos : POSITION;
  float3 bary : BARYCENTRICS;
};


float4 main(GS_OUTPUT input) : SV_Target
{
  float3 l = input.bary / fwidth(input.bary);
	return float4(min(l.x, min(l.y, l.z)).xxx, 1);
}