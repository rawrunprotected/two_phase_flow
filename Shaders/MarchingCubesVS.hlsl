#include "Definitions.h"

uint3 main(uint vertexID : SV_VertexID) : GRIDPOS
{
  uint x = vertexID % (N - 1);
  uint y = (vertexID / (N - 1)) % (N - 1);
  uint z = (vertexID / ((N - 1) * (N - 1))) % (N - 1);

  return uint3(x, y, z);
}