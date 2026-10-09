#include "flutter_window.h"
#include <optional>
#include <flutter/standard_method_codec.h>
#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project, bool widget_only, bool host_self_test)
    : project_(project), widget_only_(widget_only), host_self_test_(host_self_test) {}
FlutterWindow::~FlutterWindow() {}
void FlutterWindow::ShowMain() {
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}
bool FlutterWindow::OpenWidget() {
  if (widget_ && widget_->IsOpen()) { widget_->Reveal(); return true; }
  widget_ = std::make_unique<DesktopWidget>(
      [this](const std::string& id, bool done) {
        if (!desktop_channel_) return;
        desktop_channel_->InvokeMethod("widgetComplete",
            std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
              {flutter::EncodableValue("id"), flutter::EncodableValue(id)},
              {flutter::EncodableValue("completed"), flutter::EncodableValue(done)}}));
      }, [this] { ShowMain(); }, [this] {
        if (desktop_channel_) desktop_channel_->InvokeMethod("widgetSync", nullptr);
      }, [this] { widget_only_ = false; PostMessage(GetHandle(), kWidgetClosed, 0, 0); });
  widget_->Update(snapshot_);
  if (!widget_->Create()) { widget_.reset(); return false; }
  return true;
}
bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) return false;
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  desktop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "cn.privatetodo/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "openWidget") {
          if (OpenWidget()) result->Success();
          else result->Error("widget_unavailable", "Unable to create desktop widget");
        } else if (call.method_name() == "publishWidget") {
          const auto* state = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
          if (!state) { result->Error("invalid_argument", "Expected task state"); return; }
          snapshot_ = *state;
          if (widget_ && widget_->IsOpen()) widget_->Update(snapshot_);
          else if (widget_only_ && !OpenWidget()) { widget_only_ = false; ShowMain(); }
          result->Success();
        } else result->NotImplemented();
      });
  flutter_controller_->engine()->SetNextFrameCallback([this] {
    if (!widget_only_ || !widget_ || !widget_->IsOpen()) Show();
    if (host_self_test_) PostMessage(GetHandle(), kHostTestStart, 0, 0);
  });
  flutter_controller_->ForceRedraw();
  return true;
}
void FlutterWindow::OnDestroy() {
  widget_.reset();
  desktop_channel_.reset();
  flutter_controller_.reset();
  Win32Window::OnDestroy();
}
LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam) noexcept {
  if (message == kHostTestStart && host_self_test_) {
    if (!OpenWidget()) { PostQuitMessage(21); return 0; }
    SendMessage(hwnd, WM_CLOSE, 0, 0);
    HWND component = FindWindow(L"CN_PRIVATE_TODO_DESKTOP_WIDGET", nullptr);
    if (!IsWindow(hwnd) || IsWindowVisible(hwnd) || !component || !IsWindowVisible(component)) {
      PostQuitMessage(22); return 0;
    }
    ShowMain();
    SendMessage(component, WM_CLOSE, 0, 0);
    PostMessage(hwnd, kHostTestFinish, 0, 0);
    return 0;
  }
  if (message == kHostTestFinish && host_self_test_) {
    if (widget_ || !IsWindowVisible(hwnd)) { PostQuitMessage(23); return 0; }
    SendMessage(hwnd, WM_CLOSE, 0, 0);
    return 0;
  }
  if (message == WM_CLOSE && widget_ && widget_->IsOpen()) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  if (message == kWidgetClosed) {
    if (widget_ && !widget_->IsOpen()) {
      widget_.reset();
      widget_only_ = false;
      if (!IsWindowVisible(hwnd)) DestroyWindow(hwnd);
    }
    return 0;
  }
  if (message == kOpenWidget) { OpenWidget(); return 0; }
  if (flutter_controller_) {
    const auto result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }
  if (message == WM_FONTCHANGE && flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
