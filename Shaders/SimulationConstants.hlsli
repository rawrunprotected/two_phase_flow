cbuffer SimulationConstants : register(b0)
{
  float dt;
  float dx;
  float interfaceWidth;
  float viscosity;

  float surfaceTension;
  float levelSetDiffusion;

  uint stepSize;
}

// Using 5th order smoothstep as an approximate step function
float Heavyside(float x)
{
  x = saturate(0.5 * x / dx + 0.5);
  return x * x * x * (x * (x * 6 - 15) + 10);
}

// Derivative of the above as an approximate delta function
float delta(float x)
{
  x = saturate(0.5 * x / dx + 0.5);
  return x * x * (x * (30 * x - 60) + 30);
}