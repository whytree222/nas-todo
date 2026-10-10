#ifndef PRIVATE_TODO_GLASS_SURFACE_H_
#define PRIVATE_TODO_GLASS_SURFACE_H_
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dcomp.h>
#include <wrl/client.h>

// A premultiplied visual over the system's window material. No color-key holes.
class GlassSurface {
 public:
  bool Create(HWND hwnd);
  bool Present(int width, int height, const void* pixels, UINT stride);
  bool NativeBackdrop() const { return native_backdrop_; }
 private:
  HWND hwnd_ = nullptr;
  bool native_backdrop_ = false;
  bool layered_fallback_ = false;
  UINT width_ = 0, height_ = 0;
  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<IDXGISwapChain1> swap_chain_;
  Microsoft::WRL::ComPtr<IDCompositionDevice> composition_;
  Microsoft::WRL::ComPtr<IDCompositionTarget> target_;
  Microsoft::WRL::ComPtr<IDCompositionVisual> visual_;
  void UseFallback();
};
#endif
