#include <DirectXMath.h>
#include <cmath>

#include <DirectXTex.h>

#include "Texture3D.h"

#include "Definitions.h"

#include "Generated/MarchingCubesVS.h"
#include "Generated/MarchingCubesGS.h"
#include "Generated/MarchingCubesPS.h"

#include "Generated/SceneRenderVS.h"
#include "Generated/SceneRenderPS.h"

#include "Generated/CausticsTracingCS.h"
#include "Generated/CausticsBlurHorizontalCS.h"
#include "Generated/CausticsBlurVerticalCS.h"

using namespace DirectX;
using namespace Microsoft::WRL;

struct RenderConstants
{
  XMMATRIX projFromWorld;
  XMMATRIX worldFromProj;
  float refractionIndexPhase0 = 1.3f;
  float refractionIndexPhase1 = 1.5f;

  float causticsRadius = 3;
  float planeHeight = -0.5;
};

extern ComPtr<ID3D11Device> g_device;
extern ComPtr<ID3D11DeviceContext> g_immediateContext;
extern ComPtr<ID3D11RenderTargetView> g_rtv;

// From simulation
extern Texture3D g_phi;

// State
ComPtr<ID3D11RasterizerState> g_rasterizerState;
ComPtr<ID3D11SamplerState> g_clampSampler;

// Shaders
ComPtr<ID3D11VertexShader> g_marchingCubesVS;
ComPtr<ID3D11GeometryShader> g_marchingCubesGS;
ComPtr<ID3D11PixelShader> g_marchingCubesPS;

ComPtr<ID3D11VertexShader> g_sceneRenderVS;
ComPtr<ID3D11PixelShader> g_sceneRenderPS;

ComPtr<ID3D11ComputeShader> g_causticsTracingCS;
ComPtr<ID3D11ComputeShader> g_causticsBlurHorizontalCS;
ComPtr<ID3D11ComputeShader> g_causticsBlurVerticalCS;

// Resources
ComPtr<ID3D11Buffer> g_renderConstants;

ComPtr<ID3D11Texture2D> g_causticsMap;
ComPtr<ID3D11ShaderResourceView> g_causticsMapSrv;
ComPtr<ID3D11UnorderedAccessView> g_causticsMapUav;

ComPtr<ID3D11Texture2D> g_blurredCaustics1;
ComPtr<ID3D11ShaderResourceView> g_blurredCaustics1Srv;
ComPtr<ID3D11UnorderedAccessView> g_blurredCaustics1Uav;

ComPtr<ID3D11Texture2D> g_blurredCaustics2;
ComPtr<ID3D11ShaderResourceView> g_blurredCaustics2Srv;
ComPtr<ID3D11UnorderedAccessView> g_blurredCaustics2Uav;

ComPtr<ID3D11Texture2D> g_skyBox;
ComPtr<ID3D11ShaderResourceView> g_skyBoxSrv;

void CreateRenderResources()
{
  g_device->CreateVertexShader(MarchingCubesVS, ARRAYSIZE(MarchingCubesVS), nullptr, &g_marchingCubesVS);
  g_device->CreateGeometryShader(MarchingCubesGS, ARRAYSIZE(MarchingCubesGS), nullptr, &g_marchingCubesGS);
  g_device->CreatePixelShader(MarchingCubesPS, ARRAYSIZE(MarchingCubesPS), nullptr, &g_marchingCubesPS);

  g_device->CreateVertexShader(SceneRenderVS, ARRAYSIZE(SceneRenderVS), nullptr, &g_sceneRenderVS);
  g_device->CreatePixelShader(SceneRenderPS, ARRAYSIZE(SceneRenderPS), nullptr, &g_sceneRenderPS);

  g_device->CreateComputeShader(CausticsTracingCS, ARRAYSIZE(CausticsTracingCS), nullptr, &g_causticsTracingCS);
  g_device->CreateComputeShader(CausticsBlurHorizontalCS, ARRAYSIZE(CausticsBlurHorizontalCS), nullptr, &g_causticsBlurHorizontalCS);
  g_device->CreateComputeShader(CausticsBlurVerticalCS, ARRAYSIZE(CausticsBlurVerticalCS), nullptr, &g_causticsBlurVerticalCS);

  g_device->CreateBuffer(&CD3D11_BUFFER_DESC(sizeof RenderConstants, D3D11_BIND_CONSTANT_BUFFER, D3D11_USAGE_DYNAMIC, D3D11_CPU_ACCESS_WRITE), nullptr, &g_renderConstants);

  {
    CD3D11_RASTERIZER_DESC rasterizerDesc(D3D11_DEFAULT);
    rasterizerDesc.CullMode = D3D11_CULL_NONE;
    g_device->CreateRasterizerState(&rasterizerDesc, &g_rasterizerState);
  }

  {
    CD3D11_SAMPLER_DESC clampSamplerDesc(D3D11_DEFAULT);
    clampSamplerDesc.AddressU = clampSamplerDesc.AddressV = clampSamplerDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    g_device->CreateSamplerState(&clampSamplerDesc, &g_clampSampler);
  }

  {
    ComPtr<ID3D11Resource> resource;

    ScratchImage image;
    LoadFromDDSFile(L"SkyBox.dds", 0, nullptr, image);
    CreateTexture(g_device.Get(), image.GetImages(), image.GetImageCount(), image.GetMetadata(), &resource);

    resource.As(&g_skyBox);

    g_device->CreateShaderResourceView(g_skyBox.Get(), &CD3D11_SHADER_RESOURCE_VIEW_DESC(g_skyBox.Get(), D3D11_SRV_DIMENSION_TEXTURECUBE), &g_skyBoxSrv);
  }

  {
    g_device->CreateTexture2D(&CD3D11_TEXTURE2D_DESC(DXGI_FORMAT_R32_UINT, CAUSTICS_RESOLUTION, CAUSTICS_RESOLUTION, 1, 1, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS), nullptr, &g_causticsMap);
    g_device->CreateShaderResourceView(g_causticsMap.Get(), nullptr, &g_causticsMapSrv);
    g_device->CreateUnorderedAccessView(g_causticsMap.Get(), nullptr, &g_causticsMapUav);
  }

  {
    g_device->CreateTexture2D(&CD3D11_TEXTURE2D_DESC(DXGI_FORMAT_R11G11B10_FLOAT, CAUSTICS_RESOLUTION, CAUSTICS_RESOLUTION, 1, 1, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS), nullptr, &g_blurredCaustics1);
    g_device->CreateShaderResourceView(g_blurredCaustics1.Get(), nullptr, &g_blurredCaustics1Srv);
    g_device->CreateUnorderedAccessView(g_blurredCaustics1.Get(), nullptr, &g_blurredCaustics1Uav);
  }

  {
    g_device->CreateTexture2D(&CD3D11_TEXTURE2D_DESC(DXGI_FORMAT_R11G11B10_FLOAT, CAUSTICS_RESOLUTION, CAUSTICS_RESOLUTION, 1, 1, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS), nullptr, &g_blurredCaustics2);
    g_device->CreateShaderResourceView(g_blurredCaustics2.Get(), nullptr, &g_blurredCaustics2Srv);
    g_device->CreateUnorderedAccessView(g_blurredCaustics2.Get(), nullptr, &g_blurredCaustics2Uav);
  }
}

void Render()
{

  static float angle = 0;

  angle += 0.001f;

  float r = 1.5;

  XMVECTOR camera = XMVectorSet(r * std::cos(angle), r * std::sin(angle), 0.7f, 0.0f);
  XMVECTOR lookAt = XMVectorSet(0.0f, 0.0f, 0.0f, 0.0f);
  XMVECTOR up = XMVectorSet(0.0f, 0.0f, 1.0f, 0.0f);
  float fov = 1.2f;
  float nearPlane = 0.01f;
  float farPlane = 30.0f;

  // Create view and projection matrix
  XMMATRIX viewFromWorld = XMMatrixLookAtLH(camera, lookAt, up);
  XMMATRIX projFromView = XMMatrixPerspectiveFovLH(fov, float(WINDOW_WIDTH) / float(WINDOW_HEIGHT), nearPlane, farPlane);

  {
    RenderConstants constants;
    constants.projFromWorld = XMMatrixMultiply(viewFromWorld, projFromView);
    constants.worldFromProj = XMMatrixInverse(nullptr, constants.projFromWorld);

    D3D11_MAPPED_SUBRESOURCE map;
    g_immediateContext->Map(g_renderConstants.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &map);
    memcpy(map.pData, &constants, sizeof constants);
    g_immediateContext->Unmap(g_renderConstants.Get(), 0);
  }

  float clearColor[] = { 0, 0, 0, 0 };
  g_immediateContext->ClearRenderTargetView(g_rtv.Get(), clearColor);

  #if 0 // Debug visualization of level set via marching cubes

  {
    g_immediateContext->ClearState();

    g_immediateContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_POINTLIST);

    ID3D11Buffer* constants[] = { g_renderConstants.Get() };
    ID3D11ShaderResourceView* srvs[] = { g_phi.m_srv.Get() };

    g_immediateContext->VSSetConstantBuffers(0, ARRAYSIZE(constants), constants);
    g_immediateContext->VSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->VSSetShader(g_marchingCubesVS.Get(), nullptr, 0);

    g_immediateContext->GSSetConstantBuffers(0, ARRAYSIZE(constants), constants);
    g_immediateContext->GSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->GSSetShader(g_marchingCubesGS.Get(), nullptr, 0);

    g_immediateContext->PSSetConstantBuffers(0, ARRAYSIZE(constants), constants);
    g_immediateContext->PSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->PSSetShader(g_marchingCubesPS.Get(), nullptr, 0);

    g_immediateContext->RSSetViewports(1, &CD3D11_VIEWPORT(0.0f, 0.0f, WINDOW_WIDTH, WINDOW_HEIGHT));
    g_immediateContext->RSSetState(g_rasterizerState.Get());

    ID3D11RenderTargetView* rtvs[] = { g_rtv.Get() };
    g_immediateContext->OMSetRenderTargets(ARRAYSIZE(rtvs), rtvs, nullptr);

    g_immediateContext->Draw((N - 1) * (N - 1) * (N - 1), 0);
  }

  #else // Ray traced visualization

  {
    g_immediateContext->ClearState();

    UINT clearValues[] = { 0, 0, 0, 0 };
    g_immediateContext->ClearUnorderedAccessViewUint(g_causticsMapUav.Get(), clearValues);

    ID3D11Buffer* constants[] = { g_renderConstants.Get() };
    ID3D11ShaderResourceView* srvs[] = { g_phi.m_srv.Get() };
    ID3D11SamplerState* samplers[] = { g_clampSampler.Get() };
    ID3D11UnorderedAccessView* uavs[] = { g_causticsMapUav.Get() };

    g_immediateContext->CSSetConstantBuffers(0, ARRAYSIZE(constants), constants);
    g_immediateContext->CSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->CSSetUnorderedAccessViews(0, ARRAYSIZE(uavs), uavs, nullptr);
    g_immediateContext->CSSetSamplers(0, ARRAYSIZE(samplers), samplers);
    g_immediateContext->CSSetShader(g_causticsTracingCS.Get(), nullptr, 0);

    g_immediateContext->Dispatch(CAUSTICS_RESOLUTION / 8, CAUSTICS_RESOLUTION / 8, 1);
  }

  {
    g_immediateContext->ClearState();

    ID3D11Buffer* constants[] = { g_renderConstants.Get() };
    ID3D11ShaderResourceView* srvs[] = { g_causticsMapSrv.Get() };
    ID3D11SamplerState* samplers[] = { g_clampSampler.Get() };
    ID3D11UnorderedAccessView* uavs[] = { g_blurredCaustics1Uav.Get() };

    g_immediateContext->CSSetConstantBuffers(0, ARRAYSIZE(constants), constants);
    g_immediateContext->CSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->CSSetUnorderedAccessViews(0, ARRAYSIZE(uavs), uavs, nullptr);
    g_immediateContext->CSSetSamplers(0, ARRAYSIZE(samplers), samplers);
    g_immediateContext->CSSetShader(g_causticsBlurHorizontalCS.Get(), nullptr, 0);

    g_immediateContext->Dispatch(CAUSTICS_RESOLUTION / 8, CAUSTICS_RESOLUTION / 8, 1);
  }

  {
    g_immediateContext->ClearState();

    ID3D11Buffer* constants[] = { g_renderConstants.Get() };
    ID3D11ShaderResourceView* srvs[] = { g_blurredCaustics1Srv.Get() };
    ID3D11SamplerState* samplers[] = { g_clampSampler.Get() };
    ID3D11UnorderedAccessView* uavs[] = { g_blurredCaustics2Uav.Get() };

    g_immediateContext->CSSetConstantBuffers(0, ARRAYSIZE(constants), constants);
    g_immediateContext->CSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->CSSetUnorderedAccessViews(0, ARRAYSIZE(uavs), uavs, nullptr);
    g_immediateContext->CSSetSamplers(0, ARRAYSIZE(samplers), samplers);
    g_immediateContext->CSSetShader(g_causticsBlurVerticalCS.Get(), nullptr, 0);

    g_immediateContext->Dispatch(CAUSTICS_RESOLUTION / 8, CAUSTICS_RESOLUTION / 8, 1);
  }

  {
    g_immediateContext->ClearState();

    g_immediateContext->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    ID3D11Buffer* constants[] = { g_renderConstants.Get() };
    ID3D11ShaderResourceView* srvs[] = { g_phi.m_srv.Get(), g_skyBoxSrv.Get(), g_blurredCaustics2Srv.Get() };
    ID3D11SamplerState* samplers[] = { g_clampSampler.Get() };

    g_immediateContext->VSSetConstantBuffers(0, ARRAYSIZE(constants), constants);
    g_immediateContext->VSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->VSSetSamplers(0, ARRAYSIZE(samplers), samplers);
    g_immediateContext->VSSetShader(g_sceneRenderVS.Get(), nullptr, 0);

    g_immediateContext->PSSetConstantBuffers(0, ARRAYSIZE(constants), constants);
    g_immediateContext->PSSetShaderResources(0, ARRAYSIZE(srvs), srvs);
    g_immediateContext->PSSetSamplers(0, ARRAYSIZE(samplers), samplers);
    g_immediateContext->PSSetShader(g_sceneRenderPS.Get(), nullptr, 0);

    g_immediateContext->RSSetViewports(1, &CD3D11_VIEWPORT(0.0f, 0.0f, WINDOW_WIDTH, WINDOW_HEIGHT));
    g_immediateContext->RSSetState(g_rasterizerState.Get());

    ID3D11RenderTargetView* rtvs[] = { g_rtv.Get() };
    g_immediateContext->OMSetRenderTargets(ARRAYSIZE(rtvs), rtvs, nullptr);

    g_immediateContext->Draw(3, 0);
  }

  #endif
}
