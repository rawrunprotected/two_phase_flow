struct VS_OUTPUT
{
  float2 UV       : TEXCOORD;
  float4 position : SV_Position;
};

// Simple full screen shader
VS_OUTPUT main(uint vertexID : SV_VertexID)
{
  VS_OUTPUT output;

  float x = -1.0 + float((vertexID & 2) << 1);
  float y = -1.0 + float((vertexID & 1) << 2);

  output.position = float4(x, y, 0, 1);
  output.UV = float2(x, -y) * 0.5 + 0.5;

  return output;
}