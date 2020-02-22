#define CAUSTICS_FIXED_POINT_SCALE 256

// Pack/unpack caustics in R11G11B10 fixed point format.
uint encodeCaustics(float3 color)
{
  uint3 u = CAUSTICS_FIXED_POINT_SCALE * color + 0.5;

  return (u.x << 21) | (u.y << 10) | u.b;
}

float3 decodeCaustics(uint value)
{
  uint3 u = uint3(value >> 21, (value >> 10) & 2047, value & 1023);

  return float3(u) / CAUSTICS_FIXED_POINT_SCALE;
}