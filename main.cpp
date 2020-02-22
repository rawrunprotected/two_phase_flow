#define WIN32_MEAN_AND_LEAN

#include <Windows.h>

#include <d3d11.h>

#include <wrl/client.h>

#include "Definitions.h"

#pragma comment(lib, "d3d11")

using namespace Microsoft::WRL;

HWND g_hwnd;

ComPtr<IDXGISwapChain> g_swapChain;
ComPtr<ID3D11Device> g_device;
ComPtr<ID3D11DeviceContext> g_immediateContext;

ComPtr<ID3D11Texture2D> g_backBuffer;
ComPtr<ID3D11RenderTargetView> g_rtv;

void CreateSimulationResources();
void StepSimulation();

void CreateRenderResources();
void Render();

LRESULT CALLBACK WndProc(
  _In_ HWND   hwnd,
  _In_ UINT   uMsg,
  _In_ WPARAM wParam,
  _In_ LPARAM lParam
)
{
  switch (uMsg)
  {
  case WM_PAINT:
  {
    PAINTSTRUCT ps;
    HDC hdc = BeginPaint(hwnd, &ps);
    EndPaint(hwnd, &ps);
  }
    break;

  case WM_DESTROY:
    exit(0);
    break;

  default:
    return DefWindowProcW(hwnd, uMsg, wParam, lParam);
  }

  return 0;
}

int WINAPI wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, PWSTR pCmdLine, int nCmdShow)
{
  {
    WNDCLASSEXW wcex = {};
    wcex.cbSize = sizeof(WNDCLASSEX);
    wcex.style = CS_HREDRAW | CS_VREDRAW;
    wcex.lpfnWndProc = WndProc;
    wcex.cbClsExtra = 0;
    wcex.cbWndExtra = 0;
    wcex.hInstance = hInstance;
    wcex.hIcon = nullptr;
    wcex.hCursor = nullptr;
    wcex.hbrBackground = nullptr;
    wcex.lpszMenuName = nullptr;
    wcex.lpszClassName = L"TwoPhaseFlowWindowClass";
    wcex.hIconSm = nullptr;

    RegisterClassExW(&wcex);

    RECT rc = { 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT };
    AdjustWindowRect(&rc, WS_OVERLAPPEDWINDOW, FALSE);
    g_hwnd = CreateWindow(L"TwoPhaseFlowWindowClass", L"Two Phase Flow", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top, 0, 0, hInstance, 0);
  }

  ShowWindow(g_hwnd, nCmdShow);

  {
    UINT createDeviceFlags = 0;

    #if defined(_DEBUG)
    createDeviceFlags |= D3D11_CREATE_DEVICE_DEBUG;
    #endif

    DXGI_SWAP_CHAIN_DESC swapChainDesc = {};
    swapChainDesc.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    swapChainDesc.SampleDesc.Count = 1;
    swapChainDesc.SampleDesc.Quality = 0;
    swapChainDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swapChainDesc.BufferCount = 2;
    swapChainDesc.OutputWindow = g_hwnd;
    swapChainDesc.Windowed = TRUE;
    swapChainDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    swapChainDesc.Flags = 0;

    D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, createDeviceFlags, nullptr, 0, D3D11_SDK_VERSION, &swapChainDesc, &g_swapChain, &g_device, nullptr, &g_immediateContext);
  }

  g_swapChain->GetBuffer(0, IID_PPV_ARGS(&g_backBuffer));
  g_device->CreateRenderTargetView(g_backBuffer.Get(), nullptr, &g_rtv);

  CreateSimulationResources();
  CreateRenderResources();

  MSG msg = {};
  while (msg.message != WM_QUIT)
  {
    while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE))
    {
      TranslateMessage(&msg);
      DispatchMessageW(&msg);
    }

    StepSimulation();
    Render();
    
    g_swapChain->Present(1, 0);
  }

  return int(msg.wParam);
}