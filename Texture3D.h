#pragma once

#include <stdint.h>
#include <d3d11.h>
#include <wrl/client.h>

extern Microsoft::WRL::ComPtr<ID3D11Device> g_device;
extern Microsoft::WRL::ComPtr<ID3D11DeviceContext> g_immediateContext;

// Simple Texture3D class.
struct Texture3D
{
  Texture3D() = default;

  Texture3D(DXGI_FORMAT format, uint32_t W, uint32_t H, uint32_t D)
  {
    g_device->CreateTexture3D(&CD3D11_TEXTURE3D_DESC(format, W, H, D, 1, D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, D3D11_USAGE_DEFAULT, 0, 0), nullptr, &m_texture);
    g_device->CreateShaderResourceView(m_texture.Get(), nullptr, &m_srv);
    g_device->CreateUnorderedAccessView(m_texture.Get(), nullptr, &m_uav);

  }

  Microsoft::WRL::ComPtr<ID3D11Texture3D> m_texture;
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> m_srv;
  Microsoft::WRL::ComPtr<ID3D11UnorderedAccessView> m_uav;
};
