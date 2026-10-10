#include "glass_surface.h"
#include <dwmapi.h>
#include <cstring>

using Microsoft::WRL::ComPtr;
void GlassSurface::UseFallback() {
  swap_chain_.Reset(); visual_.Reset(); target_.Reset(); composition_.Reset();
  context_.Reset(); device_.Reset(); width_ = height_ = 0;
  native_backdrop_ = false; layered_fallback_ = true;
  const int none = 1;
  DwmSetWindowAttribute(hwnd_, static_cast<DWMWINDOWATTRIBUTE>(38), &none, sizeof(none));
  auto style = GetWindowLongPtr(hwnd_, GWL_EXSTYLE);
  SetWindowLongPtr(hwnd_, GWL_EXSTYLE, (style & ~WS_EX_NOREDIRECTIONBITMAP) | WS_EX_LAYERED);
  SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

bool GlassSurface::Create(HWND hwnd) {
  hwnd_ = hwnd;
  HRESULT result = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
      device_.GetAddressOf(), nullptr, context_.GetAddressOf());
  if (FAILED(result)) result = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
      device_.ReleaseAndGetAddressOf(), nullptr, context_.ReleaseAndGetAddressOf());
  ComPtr<IDXGIDevice> dxgi;
  if (SUCCEEDED(result)) result = device_.As(&dxgi);
  if (SUCCEEDED(result)) result = DCompositionCreateDevice(dxgi.Get(), __uuidof(IDCompositionDevice),
      reinterpret_cast<void**>(composition_.GetAddressOf()));
  if (SUCCEEDED(result)) result = composition_->CreateTargetForHwnd(hwnd_, TRUE, target_.GetAddressOf());
  if (SUCCEEDED(result)) result = composition_->CreateVisual(visual_.GetAddressOf());
  if (SUCCEEDED(result)) result = target_->SetRoot(visual_.Get());
  if (SUCCEEDED(result)) result = composition_->Commit();
  if (FAILED(result)) { UseFallback(); return true; }
  const BOOL dark = TRUE;
  DwmSetWindowAttribute(hwnd_, static_cast<DWMWINDOWATTRIBUTE>(20), &dark, sizeof(dark));
  const int round = 2;
  DwmSetWindowAttribute(hwnd_, static_cast<DWMWINDOWATTRIBUTE>(33), &round, sizeof(round));
  const MARGINS margins{-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd_, &margins);
  const int acrylic = 3;
  native_backdrop_ = SUCCEEDED(DwmSetWindowAttribute(hwnd_, static_cast<DWMWINDOWATTRIBUTE>(38),
      &acrylic, sizeof(acrylic)));
  return true;
}

bool GlassSurface::Present(int width, int height, const void* pixels, UINT stride) {
  if (!pixels || width <= 0 || height <= 0) return false;
  if (!layered_fallback_) {
    HRESULT result = S_OK;
    const UINT w = static_cast<UINT>(width), h = static_cast<UINT>(height);
    if (!swap_chain_) {
      ComPtr<IDXGIDevice> dxgi; ComPtr<IDXGIAdapter> adapter; ComPtr<IDXGIFactory2> factory;
      result = device_.As(&dxgi);
      if (SUCCEEDED(result)) result = dxgi->GetAdapter(adapter.GetAddressOf());
      if (SUCCEEDED(result)) result = adapter->GetParent(__uuidof(IDXGIFactory2),
          reinterpret_cast<void**>(factory.GetAddressOf()));
      DXGI_SWAP_CHAIN_DESC1 description{};
      description.Width = w; description.Height = h;
      description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
      description.SampleDesc.Count = 1;
      description.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
      description.BufferCount = 2;
      description.Scaling = DXGI_SCALING_STRETCH;
      description.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
      description.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
      if (SUCCEEDED(result)) result = factory->CreateSwapChainForComposition(device_.Get(), &description,
          nullptr, swap_chain_.GetAddressOf());
      if (SUCCEEDED(result)) result = visual_->SetContent(swap_chain_.Get());
      if (SUCCEEDED(result)) result = composition_->Commit();
    } else if (w != width_ || h != height_) {
      result = swap_chain_->ResizeBuffers(2, w, h, DXGI_FORMAT_B8G8R8A8_UNORM, 0);
    }
    if (SUCCEEDED(result)) {
      width_ = w; height_ = h;
      ComPtr<ID3D11Texture2D> buffer;
      result = swap_chain_->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(buffer.GetAddressOf()));
      if (SUCCEEDED(result)) {
        context_->UpdateSubresource(buffer.Get(), 0, nullptr, pixels, stride, 0);
        result = swap_chain_->Present(1, 0);
      }
    }
    if (SUCCEEDED(result)) return true;
    UseFallback();
  }
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  HDC dc = CreateCompatibleDC(nullptr); void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!bitmap || !bits) { if (bitmap) DeleteObject(bitmap); DeleteDC(dc); return false; }
  for (int row = 0; row < height; ++row) std::memcpy(static_cast<BYTE*>(bits) + static_cast<size_t>(row) * width * 4,
      static_cast<const BYTE*>(pixels) + static_cast<size_t>(row) * stride, static_cast<size_t>(width) * 4);
  auto old = SelectObject(dc, bitmap);
  RECT rect{}; GetWindowRect(hwnd_, &rect);
  POINT destination{rect.left, rect.top}, source{};
  SIZE size{width, height};
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  const bool painted = UpdateLayeredWindow(hwnd_, nullptr, &destination, &size, dc, &source, 0, &blend, ULW_ALPHA) != FALSE;
  SelectObject(dc, old); DeleteObject(bitmap); DeleteDC(dc);
  return painted;
}
