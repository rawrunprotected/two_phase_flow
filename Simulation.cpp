#include "Texture3D.h"

#include <algorithm>
#include <vector>

#include "Definitions.h"

#include "Generated/InitializeLevelSetCS.h"
#include "Generated/InjectForcesCS.h"
#include "Generated/VelocityDivergenceCS.h"
#include "Generated/SubtractPressureGradientCS.h"
#include "Generated/AdvectFieldsCS.h"
#include "Generated/ReconstructZeroLevelCS.h"
#include "Generated/JumpFloodLevelSetCS.h"
#include "Generated/AdjustLevelSetVolumeCS.h"
#include "Generated/ComputeLevelSetVolumeCS.h"

#include "Generated/PressureSolvePass1CS.h"
#include "Generated/PressureSolvePass2CS.h"
#include "Generated/PressureSolvePass3CS.h"

#include "Generated/LevelSetDiffusionPass1CS.h"
#include "Generated/LevelSetDiffusionPass2CS.h"
#include "Generated/LevelSetDiffusionPass3CS.h"
#include "Generated/LevelSetDiffusionPass4CS.h"
#include "Generated/LevelSetDiffusionPass5CS.h"

#include "Generated/ViscositySmoothingPassCS.h"
#include "Generated/ViscosityRestrictResidualCS.h"
#include "Generated/ViscosityProlongateSolutionCS.h"

using namespace Microsoft::WRL;

struct SimulationConstants
{
  float dt = 1.0f / 60.0f;
  float dx = 1.0f / N;
  float interfaceWidth = 2.0f;
  float viscosity = 0.001f;

  float surfaceTension = 0.5f;
  float levelSetDiffusion = 5.0f;

  uint32_t stepSize = 0;

  uint32_t padding[1];
} g_constants;

// Shaders
ComPtr<ID3D11ComputeShader> g_initializeLevelSetCS;
ComPtr<ID3D11ComputeShader> g_injectForcesCS;
ComPtr<ID3D11ComputeShader> g_velocityDivergenceCS;
ComPtr<ID3D11ComputeShader> g_subtractPressureGradientCS;
ComPtr<ID3D11ComputeShader> g_advectFieldsCS;
ComPtr<ID3D11ComputeShader> g_reconstructZeroLevelCS;
ComPtr<ID3D11ComputeShader> g_jumpFloodLevelSetCS;
ComPtr<ID3D11ComputeShader> g_adjustLevelSetVolumeCS;
ComPtr<ID3D11ComputeShader> g_computeLevelSetVolumeCS;

ComPtr<ID3D11ComputeShader> g_viscositySmoothingPassCS;
ComPtr<ID3D11ComputeShader> g_viscosityRestrictResidualCS;
ComPtr<ID3D11ComputeShader> g_viscosityProlongateSolutionCS;

ComPtr<ID3D11ComputeShader> g_pressureSolvePass1CS;
ComPtr<ID3D11ComputeShader> g_pressureSolvePass2CS;
ComPtr<ID3D11ComputeShader> g_pressureSolvePass3CS;

ComPtr<ID3D11ComputeShader> g_levelSetDiffusionPass1CS;
ComPtr<ID3D11ComputeShader> g_levelSetDiffusionPass2CS;
ComPtr<ID3D11ComputeShader> g_levelSetDiffusionPass3CS;
ComPtr<ID3D11ComputeShader> g_levelSetDiffusionPass4CS;
ComPtr<ID3D11ComputeShader> g_levelSetDiffusionPass5CS;

// Resources
ComPtr<ID3D11Buffer> g_constantBuffer;

ComPtr<ID3D11Buffer> g_volumeBuffer;
ComPtr<ID3D11ShaderResourceView> g_volumeBufferSrv;
ComPtr<ID3D11UnorderedAccessView> g_volumeBufferUav;

// Level set
Texture3D g_phi;
Texture3D g_phiDiffused;

Texture3D g_phiScratch;

// Velocities
Texture3D g_velocityU;
Texture3D g_velocityV;
Texture3D g_velocityW;

// Subgrids for viscosisty solver
const uint32_t iterationDepth = 5;
Texture3D g_velocitySubGridU[iterationDepth];
Texture3D g_velocitySubGridV[iterationDepth];
Texture3D g_velocitySubGridW[iterationDepth];

Texture3D g_velocitySubGridUScratch[iterationDepth];
Texture3D g_velocitySubGridVScratch[iterationDepth];
Texture3D g_velocitySubGridWScratch[iterationDepth];

Texture3D g_residualsU[iterationDepth];
Texture3D g_residualsV[iterationDepth];
Texture3D g_residualsW[iterationDepth];

Texture3D g_velocityScratchU1;
Texture3D g_velocityScratchV1;
Texture3D g_velocityScratchW1;

Texture3D g_velocityScratchU2;
Texture3D g_velocityScratchV2;
Texture3D g_velocityScratchW2;

Texture3D g_velocityDiv;

Texture3D g_pressure;
Texture3D g_pressureScratch;

void UpdateConstants()
{
  D3D11_MAPPED_SUBRESOURCE map;
  g_immediateContext->Map(g_constantBuffer.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &map);
  memcpy(map.pData, &g_constants, sizeof g_constants);
  g_immediateContext->Unmap(g_constantBuffer.Get(), 0);
}

void Dispatch(const ComPtr<ID3D11ComputeShader>& shader, uint32_t W, uint32_t H, uint32_t D, std::initializer_list<Texture3D> inputs, std::initializer_list<Texture3D> outputs)
{
  g_immediateContext->ClearState();

  std::vector<ID3D11ShaderResourceView*> srvs;
  for (auto& texture : inputs)
  {
    srvs.push_back(texture.m_srv.Get());
  }

  std::vector<ID3D11UnorderedAccessView*> uavs;
  for (auto& texture : outputs)
  {
    uavs.push_back(texture.m_uav.Get());
  }

  ID3D11Buffer* constantsBuffers[] = { g_constantBuffer.Get() };

  g_immediateContext->CSSetConstantBuffers(0, ARRAYSIZE(constantsBuffers), constantsBuffers);
  g_immediateContext->CSSetShaderResources(0, UINT(srvs.size()), srvs.data());
  g_immediateContext->CSSetUnorderedAccessViews(0, UINT(uavs.size()), uavs.data(), nullptr);
  g_immediateContext->CSSetShader(shader.Get(), nullptr, 0);

  g_immediateContext->Dispatch(W, H, D);
}

void FixUpLevelSet()
{
  Dispatch(g_reconstructZeroLevelCS, N / 4, N / 4, N / 4, { g_phi }, { g_phiScratch });
  std::swap(g_phi, g_phiScratch);

  for (uint32_t stepSize = N / 2; stepSize >= 1; stepSize /= 2)
  {
    g_constants.stepSize = stepSize;
    UpdateConstants();

    Dispatch(g_jumpFloodLevelSetCS, N / 4, N / 4, N / 4, { g_phi }, { g_phiScratch });
    std::swap(g_phi, g_phiScratch);
  }

  {
    g_immediateContext->ClearState();
    ID3D11ShaderResourceView* srvs[] = { g_volumeBufferSrv.Get() };
    ID3D11UnorderedAccessView* uavs[] = { g_phi.m_uav.Get() };
    ID3D11Buffer* constantsBuffers[] = { g_constantBuffer.Get() };

    g_immediateContext->CSSetConstantBuffers(0, ARRAYSIZE(constantsBuffers), constantsBuffers);
    g_immediateContext->CSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->CSSetUnorderedAccessViews(0, ARRAYSIZE(uavs), uavs, nullptr);
    g_immediateContext->CSSetShader(g_adjustLevelSetVolumeCS.Get(), nullptr, 0);

    g_immediateContext->Dispatch(1, 1, 1);
  }
}

void CreateSimulationResources()
{
  g_device->CreateBuffer(&CD3D11_BUFFER_DESC(sizeof SimulationConstants, D3D11_BIND_CONSTANT_BUFFER, D3D11_USAGE_DYNAMIC, D3D11_CPU_ACCESS_WRITE), nullptr, &g_constantBuffer);

  g_device->CreateBuffer(&CD3D11_BUFFER_DESC(4, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS), nullptr, &g_volumeBuffer);
  g_device->CreateShaderResourceView(g_volumeBuffer.Get(), &CD3D11_SHADER_RESOURCE_VIEW_DESC(g_volumeBuffer.Get(), DXGI_FORMAT_R32_FLOAT, 0, 1), &g_volumeBufferSrv);
  g_device->CreateUnorderedAccessView(g_volumeBuffer.Get(), &CD3D11_UNORDERED_ACCESS_VIEW_DESC(g_volumeBuffer.Get(), DXGI_FORMAT_R32_FLOAT, 0, 1), &g_volumeBufferUav);

  g_phi = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);
  g_phiScratch = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);
  g_phiDiffused = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);

  g_velocityU = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);
  g_velocityV = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);
  g_velocityW = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);

  for (uint32_t level = 0; level < iterationDepth; ++level)
  {
    g_velocitySubGridU[level] = Texture3D(DXGI_FORMAT_R32_FLOAT, N >> level, N >> level, N >> level);
    g_velocitySubGridV[level] = Texture3D(DXGI_FORMAT_R32_FLOAT, N >> level, N >> level, N >> level);
    g_velocitySubGridW[level] = Texture3D(DXGI_FORMAT_R32_FLOAT, N >> level, N >> level, N >> level);

    g_velocitySubGridUScratch[level] = Texture3D(DXGI_FORMAT_R32_FLOAT, N >> level, N >> level, N >> level);
    g_velocitySubGridVScratch[level] = Texture3D(DXGI_FORMAT_R32_FLOAT, N >> level, N >> level, N >> level);
    g_velocitySubGridWScratch[level] = Texture3D(DXGI_FORMAT_R32_FLOAT, N >> level, N >> level, N >> level);

    g_residualsU[level] = Texture3D(DXGI_FORMAT_R32_FLOAT, N >> (level + 1), N >> (level + 1), N >> (level + 1));
    g_residualsV[level] = Texture3D(DXGI_FORMAT_R32_FLOAT, N >> (level + 1), N >> (level + 1), N >> (level + 1));
    g_residualsW[level] = Texture3D(DXGI_FORMAT_R32_FLOAT, N >> (level + 1), N >> (level + 1), N >> (level + 1));
  }

  g_velocityScratchU1 = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);
  g_velocityScratchV1 = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);
  g_velocityScratchW1 = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);

  g_velocityScratchU2 = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);
  g_velocityScratchV2 = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);
  g_velocityScratchW2 = Texture3D(DXGI_FORMAT_R32_FLOAT, N, N, N);

  g_velocityDiv = Texture3D(DXGI_FORMAT_R32_FLOAT, N + 1, N + 1, N + 1);

  g_pressure = Texture3D(DXGI_FORMAT_R32_FLOAT, N + 1, N + 1, N + 1);
  g_pressureScratch = Texture3D(DXGI_FORMAT_R32_FLOAT, N + 1, N + 1, N + 1);

  g_device->CreateComputeShader(InitializeLevelSetCS, ARRAYSIZE(InitializeLevelSetCS), nullptr, &g_initializeLevelSetCS);
  g_device->CreateComputeShader(InjectForcesCS, ARRAYSIZE(InjectForcesCS), nullptr, &g_injectForcesCS);
  g_device->CreateComputeShader(VelocityDivergenceCS, ARRAYSIZE(VelocityDivergenceCS), nullptr, &g_velocityDivergenceCS);
  g_device->CreateComputeShader(SubtractPressureGradientCS, ARRAYSIZE(SubtractPressureGradientCS), nullptr, &g_subtractPressureGradientCS);
  g_device->CreateComputeShader(AdvectFieldsCS, ARRAYSIZE(AdvectFieldsCS), nullptr, &g_advectFieldsCS);
  g_device->CreateComputeShader(ReconstructZeroLevelCS, ARRAYSIZE(ReconstructZeroLevelCS), nullptr, &g_reconstructZeroLevelCS);
  g_device->CreateComputeShader(JumpFloodLevelSetCS, ARRAYSIZE(JumpFloodLevelSetCS), nullptr, &g_jumpFloodLevelSetCS);
  g_device->CreateComputeShader(AdjustLevelSetVolumeCS, ARRAYSIZE(AdjustLevelSetVolumeCS), nullptr, &g_adjustLevelSetVolumeCS);
  g_device->CreateComputeShader(ComputeLevelSetVolumeCS, ARRAYSIZE(ComputeLevelSetVolumeCS), nullptr, &g_computeLevelSetVolumeCS);

  g_device->CreateComputeShader(PressureSolvePass1CS, ARRAYSIZE(PressureSolvePass1CS), nullptr, &g_pressureSolvePass1CS);
  g_device->CreateComputeShader(PressureSolvePass2CS, ARRAYSIZE(PressureSolvePass2CS), nullptr, &g_pressureSolvePass2CS);
  g_device->CreateComputeShader(PressureSolvePass3CS, ARRAYSIZE(PressureSolvePass3CS), nullptr, &g_pressureSolvePass3CS);

  g_device->CreateComputeShader(LevelSetDiffusionPass1CS, ARRAYSIZE(LevelSetDiffusionPass1CS), nullptr, &g_levelSetDiffusionPass1CS);
  g_device->CreateComputeShader(LevelSetDiffusionPass2CS, ARRAYSIZE(LevelSetDiffusionPass2CS), nullptr, &g_levelSetDiffusionPass2CS);
  g_device->CreateComputeShader(LevelSetDiffusionPass3CS, ARRAYSIZE(LevelSetDiffusionPass3CS), nullptr, &g_levelSetDiffusionPass3CS);
  g_device->CreateComputeShader(LevelSetDiffusionPass4CS, ARRAYSIZE(LevelSetDiffusionPass4CS), nullptr, &g_levelSetDiffusionPass4CS);
  g_device->CreateComputeShader(LevelSetDiffusionPass5CS, ARRAYSIZE(LevelSetDiffusionPass5CS), nullptr, &g_levelSetDiffusionPass5CS);

  g_device->CreateComputeShader(ViscositySmoothingPassCS, ARRAYSIZE(ViscositySmoothingPassCS), nullptr, &g_viscositySmoothingPassCS);
  g_device->CreateComputeShader(ViscosityRestrictResidualCS, ARRAYSIZE(ViscosityRestrictResidualCS), nullptr, &g_viscosityRestrictResidualCS);
  g_device->CreateComputeShader(ViscosityProlongateSolutionCS, ARRAYSIZE(ViscosityProlongateSolutionCS), nullptr, &g_viscosityProlongateSolutionCS);

  UpdateConstants();

  Dispatch(g_initializeLevelSetCS, N, N, N, {}, { g_phi });

  {
    g_immediateContext->ClearState();
    ID3D11ShaderResourceView* srvs[] = { g_phi.m_srv.Get() };
    ID3D11UnorderedAccessView* uavs[] = { g_volumeBufferUav.Get() };
    ID3D11Buffer* constantsBuffers[] = { g_constantBuffer.Get() };

    g_immediateContext->CSSetConstantBuffers(0, ARRAYSIZE(constantsBuffers), constantsBuffers);
    g_immediateContext->CSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->CSSetUnorderedAccessViews(0, ARRAYSIZE(uavs), uavs, nullptr);
    g_immediateContext->CSSetShader(g_computeLevelSetVolumeCS.Get(), nullptr, 0);

    g_immediateContext->Dispatch(1, 1, 1);
  }

  FixUpLevelSet();
}

void StepSimulation()
{
  UpdateConstants();

  // Diffuse level set for smooth surface tension
  {
    Dispatch(g_levelSetDiffusionPass1CS, N / 8, N / 8, 1, { g_phi }, { g_phiDiffused });
    Dispatch(g_levelSetDiffusionPass2CS, N / 8, N / 8, 1, { g_phiDiffused }, { g_phiScratch });
    Dispatch(g_levelSetDiffusionPass3CS, N / 8, N / 8, 1, { g_phiScratch }, { g_phiDiffused });
    Dispatch(g_levelSetDiffusionPass4CS, N / 8, N / 8, 1, { g_phiDiffused }, { g_phiScratch });
    Dispatch(g_levelSetDiffusionPass5CS, N / 8, N / 8, 1, { g_phiScratch }, { g_phiDiffused });
  }

  // Inject forces
  {
    Dispatch(g_injectForcesCS, N / 4, N / 4, N / 4, { g_phi, g_phiDiffused }, { g_velocityU, g_velocityV, g_velocityW });
  }

  // Multi-grid viscosity
  {
    Dispatch(g_viscositySmoothingPassCS, N / 4, N / 4, N / 4,
      { g_velocityU, g_velocityV, g_velocityW, g_velocityU, g_velocityV, g_velocityW },
      { g_velocitySubGridU[0], g_velocitySubGridV[0], g_velocitySubGridW[0] });

    Dispatch(g_viscosityRestrictResidualCS, N / 8, N / 8, N / 8,
      { g_velocitySubGridU[0], g_velocitySubGridV[0], g_velocitySubGridW[0], g_velocityU, g_velocityV, g_velocityW },
      { g_residualsU[0], g_residualsV[0], g_residualsW[0] });


    g_constants.dx *= 2;
    UpdateConstants();

    {
      Dispatch(g_viscositySmoothingPassCS, N / 8, N / 8, N / 8,
        { {}, {}, {}, g_residualsU[0], g_residualsV[0], g_residualsW[0] },
        { g_velocitySubGridU[1], g_velocitySubGridV[1], g_velocitySubGridW[1] });

      Dispatch(g_viscosityRestrictResidualCS, N / 16, N / 16, N / 16,
        { g_velocitySubGridU[1], g_velocitySubGridV[1], g_velocitySubGridW[1], g_residualsU[0], g_residualsV[0], g_residualsW[0] },
        { g_residualsU[1], g_residualsV[1], g_residualsW[1] });

      g_constants.dx *= 2;
      UpdateConstants();

      {
        Dispatch(g_viscositySmoothingPassCS, N / 16, N / 16, N / 16,
          { {}, {}, {}, g_residualsU[1], g_residualsV[1], g_residualsW[1] },
          { g_velocitySubGridU[2], g_velocitySubGridV[2], g_velocitySubGridW[2] });

        Dispatch(g_viscosityRestrictResidualCS, N / 32, N / 32, N / 32,
          { g_velocitySubGridU[2], g_velocitySubGridV[2], g_velocitySubGridW[2], g_residualsU[1], g_residualsV[1], g_residualsW[1] },
          { g_residualsU[2], g_residualsV[2], g_residualsW[2] });

        g_constants.dx *= 2;
        UpdateConstants();
        {
          Dispatch(g_viscositySmoothingPassCS, N / 32, N / 32, N / 32,
            { {}, {}, {}, g_residualsU[2], g_residualsV[2], g_residualsW[2] },
            { g_velocitySubGridU[3], g_velocitySubGridV[3], g_velocitySubGridW[3] });
        }
        g_constants.dx /= 2;
        UpdateConstants();

        Dispatch(g_viscosityProlongateSolutionCS, N / 16, N / 16, N / 16,
          { g_velocitySubGridU[3], g_velocitySubGridV[3], g_velocitySubGridW[3] },
          { g_velocitySubGridU[2], g_velocitySubGridV[2], g_velocitySubGridW[2] });

        Dispatch(g_viscositySmoothingPassCS, N / 16, N / 16, N / 16,
          { g_velocitySubGridU[2], g_velocitySubGridV[2], g_velocitySubGridW[2], g_residualsU[1], g_residualsV[1], g_residualsW[1] },
          { g_velocitySubGridUScratch[2], g_velocitySubGridVScratch[2], g_velocitySubGridWScratch[2] });

        std::swap(g_velocitySubGridU[2], g_velocitySubGridUScratch[2]);
        std::swap(g_velocitySubGridV[2], g_velocitySubGridVScratch[2]);
        std::swap(g_velocitySubGridW[2], g_velocitySubGridWScratch[2]);
      }

      g_constants.dx /= 2;
      UpdateConstants();

      Dispatch(g_viscosityProlongateSolutionCS, N / 8, N / 8, N / 8,
        { g_velocitySubGridU[2], g_velocitySubGridV[2], g_velocitySubGridW[2] },
        { g_velocitySubGridU[1], g_velocitySubGridV[1], g_velocitySubGridW[1] });

      Dispatch(g_viscositySmoothingPassCS, N / 8, N / 8, N / 8,
        { g_velocitySubGridU[1], g_velocitySubGridV[1], g_velocitySubGridW[1], g_residualsU[0], g_residualsV[0], g_residualsW[0] },
        { g_velocitySubGridUScratch[1], g_velocitySubGridVScratch[1], g_velocitySubGridWScratch[1] });

      std::swap(g_velocitySubGridU[1], g_velocitySubGridUScratch[1]);
      std::swap(g_velocitySubGridV[1], g_velocitySubGridVScratch[1]);
      std::swap(g_velocitySubGridW[1], g_velocitySubGridWScratch[1]);
    }

    g_constants.dx /= 2;
    UpdateConstants();

    Dispatch(g_viscosityProlongateSolutionCS, N / 4, N / 4, N / 4,
      { g_velocitySubGridU[1], g_velocitySubGridV[1], g_velocitySubGridW[1] },
      { g_velocitySubGridU[0], g_velocitySubGridV[0], g_velocitySubGridW[0] });

    Dispatch(g_viscositySmoothingPassCS, N / 4, N / 4, N / 4,
      { g_velocitySubGridU[0], g_velocitySubGridV[0], g_velocitySubGridW[0], g_velocityU, g_velocityV, g_velocityW },
      { g_velocityScratchU1, g_velocityScratchV1, g_velocityScratchW1 });

    Dispatch(g_viscosityRestrictResidualCS, N / 8, N / 8, N / 8,
      { g_velocityScratchU1, g_velocityScratchV1, g_velocityScratchW1, g_velocityU, g_velocityV, g_velocityW },
      { g_residualsU[0], g_residualsV[0], g_residualsW[0] });

    std::swap(g_velocityU, g_velocityScratchU1);
    std::swap(g_velocityV, g_velocityScratchV1);
    std::swap(g_velocityW, g_velocityScratchW1);
  }

  // Compute divergence of velocity
  {
    Dispatch(g_velocityDivergenceCS, N / 4 + 1, N / 4 + 1, N / 4 + 1, { g_velocityU, g_velocityV, g_velocityW }, { g_velocityDiv });
  }

  // Solve for pressure
  {
    Dispatch(g_pressureSolvePass1CS, N / 8 + 1, N / 8 + 1, 1, { g_velocityDiv }, { g_pressure });
    Dispatch(g_pressureSolvePass2CS, N / 8 + 1, N / 8 + 1, 1, { g_pressure }, { g_pressureScratch });
    Dispatch(g_pressureSolvePass3CS, N / 8 + 1, N / 8 + 1, 1, { g_pressureScratch }, { g_pressure });
    Dispatch(g_pressureSolvePass2CS, N / 8 + 1, N / 8 + 1, 1, { g_pressure }, { g_pressureScratch });
    Dispatch(g_pressureSolvePass1CS, N / 8 + 1, N / 8 + 1, 1, { g_pressureScratch }, { g_pressure });
  }

  // Project velocity
  {
    Dispatch(g_subtractPressureGradientCS, N / 4, N / 4, N / 4, { g_pressure }, { g_velocityU, g_velocityV, g_velocityW });
  }

  // Advect parameters
  {
    Dispatch(g_advectFieldsCS, N / 4, N / 4, N / 4, { g_velocityU, g_velocityV, g_velocityW, g_phi }, { g_velocityScratchU1, g_velocityScratchV1, g_velocityScratchW1, g_phiScratch });

    std::swap(g_phi, g_phiScratch);
    std::swap(g_velocityU, g_velocityScratchU1);
    std::swap(g_velocityV, g_velocityScratchV1);
    std::swap(g_velocityW, g_velocityScratchW1);
  }

  // Level set maintenance
  FixUpLevelSet();
}