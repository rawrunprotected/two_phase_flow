#include "Definitions.h"

#include "SimulationConstants.hlsli"

RWTexture3D<float> u : register(u0);
RWTexture3D<float> v : register(u1);
RWTexture3D<float> w : register(u2);

Texture3D<float> phi : register(t0);
Texture3D<float> phiDiffused : register(t1);

[numthreads(4, 4, 4)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID)
{
  float3 surfaceTensionForce;
  {
    // Evaluate curvature as div(normalize(grad(phi))) from the diffused level set
    int x = dispatchThreadID.x;
    int y = dispatchThreadID.y;
    int z = dispatchThreadID.z;

    // Sample indices clamped to border - this results in virtually extending the level set through the boundaries,
    // giving the solution for a 90deg contact angle.
    int xp = min(x + 1, N - 1);
    int xm = max(x - 1, 0);
    int yp = min(y + 1, N - 1);
    int ym = max(y - 1, 0);
    int zp = min(z + 1, N - 1);
    int zm = max(z - 1, 0);

    float phi_000 = phiDiffused[uint3(x, y, z)];
    float phi_p00 = phiDiffused[uint3(xp, y, z)];
    float phi_m00 = phiDiffused[uint3(xm, y, z)];
    float phi_0p0 = phiDiffused[uint3(x, yp, z)];
    float phi_0m0 = phiDiffused[uint3(x, ym, z)];
    float phi_00p = phiDiffused[uint3(x, y, zp)];
    float phi_00m = phiDiffused[uint3(x, y, zm)];
    float phi_pp0 = phiDiffused[uint3(xp, yp, z)];
    float phi_mm0 = phiDiffused[uint3(xm, ym, z)];
    float phi_mp0 = phiDiffused[uint3(xm, yp, z)];
    float phi_pm0 = phiDiffused[uint3(xp, ym, z)];
    float phi_p0p = phiDiffused[uint3(xp, y, zp)];
    float phi_m0m = phiDiffused[uint3(xm, y, zm)];
    float phi_m0p = phiDiffused[uint3(xm, y, zp)];
    float phi_p0m = phiDiffused[uint3(xp, y, zm)];
    float phi_0pp = phiDiffused[uint3(x, yp, zp)];
    float phi_0mm = phiDiffused[uint3(x, ym, zm)];
    float phi_0mp = phiDiffused[uint3(x, ym, zp)];
    float phi_0pm = phiDiffused[uint3(x, yp, zm)];

    // Level set derivatives
    float phi_x = 0.5 * (phi_p00 - phi_m00) / dx;
    float phi_y = 0.5 * (phi_0p0 - phi_0m0) / dx;
    float phi_z = 0.5 * (phi_00p - phi_00m) / dx;

    float phi_xx = (phi_m00 + phi_p00 - 2 * phi_000) / (dx * dx);
    float phi_yy = (phi_0m0 + phi_0p0 - 2 * phi_000) / (dx * dx);
    float phi_zz = (phi_00m + phi_00p - 2 * phi_000) / (dx * dx);

    float phi_xy = 0.25 * (phi_pp0 + phi_mm0 - phi_mp0 - phi_pm0) / (dx * dx);
    float phi_xz = 0.25 * (phi_p0p + phi_m0m - phi_m0p - phi_p0m) / (dx * dx);
    float phi_yz = 0.25 * (phi_0pp + phi_0mm - phi_0mp - phi_0pm) / (dx * dx);

    float phi_x2 = phi_x * phi_x;
    float phi_y2 = phi_y * phi_y;
    float phi_z2 = phi_z * phi_z;

    // Mean curvature
    float k0 = phi_x2 * (phi_yy + phi_zz) + phi_y2 * (phi_xx + phi_zz) + phi_z2 * (phi_xx + phi_yy) - 2 * (phi_x * phi_y * phi_xy + phi_x * phi_z * phi_xz + phi_y * phi_z * phi_yz);
    float k1 = phi_x2 + phi_y2 + phi_z2;

    float k = k0 / sqrt(k1 * k1 * k1 + 1e-16);

    surfaceTensionForce = -surfaceTension * float3(phi_x, phi_y, phi_z) * k * delta(phi_000 / levelSetDiffusion) / levelSetDiffusion;
  }

   // Simple Bousinessq-ish gravity
  float3 gravity = float3(0, 0, -0.5 * sign(phi[dispatchThreadID]));

  float3 totalForce = surfaceTensionForce + gravity;

  u[dispatchThreadID] += dt * totalForce.x;
  v[dispatchThreadID] += dt * totalForce.y;
  w[dispatchThreadID] += dt * totalForce.z;
}
