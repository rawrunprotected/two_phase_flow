#include "Definitions.h"

#include "RenderConstants.hlsli"

Texture3D<float> phi : register(t0);

// Adapted from Cory Bloyd's public domain Marching Cubes implementation.
// http://paulbourke.net/geometry/polygonise/marchingsource.cpp

static const int edgeFlags[16] =
{
  0x00, 0x0d, 0x13, 0x1e, 0x26, 0x2b, 0x35, 0x38, 0x38, 0x35, 0x2b, 0x26, 0x1e, 0x13, 0x0d, 0x00
};

static const int edgeConnection[6][2] =
{
  {0,1},  {1,2},  {2,0},  {0,3},  {1,3},  {2,3}
};

static const int a2iTetrahedronTriangles[16][7] =
{
  {-1, -1, -1, -1, -1, -1, -1},
  { 0,  3,  2, -1, -1, -1, -1},
  { 0,  1,  4, -1, -1, -1, -1},
  { 1,  4,  2,  2,  4,  3, -1},

  { 1,  2,  5, -1, -1, -1, -1},
  { 0,  3,  5,  0,  5,  1, -1},
  { 0,  2,  5,  0,  5,  4, -1},
  { 5,  4,  3, -1, -1, -1, -1},

  { 3,  4,  5, -1, -1, -1, -1},
  { 4,  5,  0,  5,  2,  0, -1},
  { 1,  5,  0,  5,  3,  0, -1},
  { 5,  2,  1, -1, -1, -1, -1},

  { 3,  4,  2,  2,  4,  1, -1},
  { 4,  1,  0, -1, -1, -1, -1},
  { 2,  3,  0, -1, -1, -1, -1},
  {-1, -1, -1, -1, -1, -1, -1},
};

static const int a2iTetrahedronsInACube[6][4] =
{
  {0,5,1,6},
  {0,1,2,6},
  {0,2,3,6},
  {0,3,7,6},
  {0,7,4,6},
  {0,4,5,6},
};

static const int3 corners[8] =
{
  int3(0, 0, 0),
  int3(1, 0, 0),
  int3(1, 1, 0),
  int3(0, 1, 0),
  int3(0, 0, 1),
  int3(1, 0, 1),
  int3(1, 1, 1),
  int3(0, 1, 1)
};

struct GS_OUTPUT
{
  float4 position : SV_Position;
  float3 worldpos : POSITION;
  float3 bary : BARYCENTRICS;
};

[maxvertexcount(36)]
void main(point uint3 input[1] : GRIDPOS, inout TriangleStream<GS_OUTPUT> stream)
{
  int3 corner[8];
  // Generate cube corner integer offsets
  for (int i = 0; i < 8; i++)
    corner[i] = input[0] + corners[i];

  float value[8];

  int signCount = 0;

  // Load cube corner values
  [unroll]
  for (int i = 0; i < 8; i++)
  {
    value[i] = phi[corner[i]];
    if (value[i] < 0)
      signCount++;
  }

  // Early out
  if (signCount == 0 || signCount == 8)
    return;

  [unroll]
  for (int i = 0; i < 6; i++)
  {
    // Set tetrahedron corners and values
    float4 tCorner[4] = {
      float4(0, 0, 0, 1),
      float4(0, 0, 0, 1),
      float4(0, 0, 0, 1),
      float4(0, 0, 0, 1)
    };

    float tValue[4];
    [unroll]
    for (int j = 0; j < 4; j++)
    {
      int v = a2iTetrahedronsInACube[i][j];
      tCorner[j].xyz = corner[v];
      tValue[j] = value[v];
    }

    // Generate sign configuration
    int conf = 0;
    [unroll]
    for (int j = 0; j < 4; j++)
    {
      if (tValue[j] < 0)
      {
        conf += 1 << j;
      }
    }

    int flags = edgeFlags[conf];

    if (flags == 0)
      continue;

    float4 edgeVertex[6] = {
      float4(0, 0, 0, 1),
      float4(0, 0, 0, 1),
      float4(0, 0, 0, 1),
      float4(0, 0, 0, 1),
      float4(0, 0, 0, 1),
      float4(0, 0, 0, 1)
    };

    [unroll]
    for (int j = 0; j < 6; j++)
    {
      if (flags & (1 << j))
      {
        int v0 = edgeConnection[j][0];
        int v1 = edgeConnection[j][1];
        float f0 = tValue[v0];
        float f1 = tValue[v1];

        edgeVertex[j] = lerp(tCorner[v0], tCorner[v1], f0 / (f0 - f1));
      }
    }

    [unroll]
    for (int j = 0; j < 2; j++)
    {
      if (a2iTetrahedronTriangles[conf][3 * j] < 0)
        break;

      [unroll]
      for (int k = 0; k < 3; k++)
      {
        GS_OUTPUT output;
        output.position = edgeVertex[a2iTetrahedronTriangles[conf][3 * j + k]];
        output.position.xyz /= (N - 1);
        output.position.xyz -= 0.5.xxx;
        output.worldpos = output.position.xyz;
        output.position = mul(projFromWorld, output.position);
        output.bary = k.xxx == int3(0, 1, 2);
        stream.Append(output);
      }

      stream.RestartStrip();
    }
  }
}