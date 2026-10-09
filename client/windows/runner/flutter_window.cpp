#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  desktop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "cn.privatetodo/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HWND hwnd = GetHandle();
        if (call.method_name() == "startDrag") {
          ReleaseCapture();
          POINT cursor{};
          GetCursorPos(&cursor);
          PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, MAKELPARAM(cursor.x, cursor.y));
          result->Success();
          return;
        }
        const bool* value = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
        if (!value) {
          result->Error("invalid_argument", "Expected a boolean");
          return;
        }
        if (call.method_name() == "setPinned") {
          SetWindowPos(hwnd, *value ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        } else if (call.method_name() == "setCompact") {
          if (*value != compact_) {
            compact_ = *value;
            if (compact_) {
              GetWindowRect(hwnd, &normal_rect_);
              normal_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
              SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_THICKFRAME | WS_VISIBLE);
              const double scale = GetDpiForWindow(hwnd) / 96.0;
              SetWindowPos(hwnd, HWND_NOTOPMOST, normal_rect_.left, normal_rect_.top,
                           static_cast<int>(380 * scale), static_cast<int>(520 * scale),
                           SWP_FRAMECHANGED | SWP_SHOWWINDOW);
            } else {
              SetWindowLongPtr(hwnd, GWL_STYLE, normal_style_);
              SetWindowPos(hwnd, HWND_NOTOPMOST, normal_rect_.left, normal_rect_.top,
                           normal_rect_.right - normal_rect_.left,
                           normal_rect_.bottom - normal_rect_.top,
                           SWP_FRAMECHANGED | SWP_SHOWWINDOW);
            }
          }
        } else {
          result->NotImplemented();
          return;
        }
        result->Success();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  desktop_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO:
      if (compact_) {
        auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
        const double scale = GetDpiForWindow(hwnd) / 96.0;
        limits->ptMinTrackSize.x = static_cast<LONG>(320 * scale);
        limits->ptMinTrackSize.y = static_cast<LONG>(280 * scale);
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
