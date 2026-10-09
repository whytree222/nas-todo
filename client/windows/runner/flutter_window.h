#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32_window.h"
#include "desktop_widget.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project, bool widget_only = false,
                         bool host_self_test = false);
  virtual ~FlutterWindow();
  static constexpr UINT kOpenWidget = WM_APP + 44;

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> desktop_channel_;
  bool OpenWidget();
  void ShowMain();
  std::unique_ptr<DesktopWidget> widget_;
  flutter::EncodableMap snapshot_;
  bool widget_only_ = false;
  bool host_self_test_ = false;
  static constexpr UINT kWidgetClosed = WM_APP + 43;
  static constexpr UINT kHostTestStart = WM_APP + 46;
  static constexpr UINT kHostTestFinish = WM_APP + 47;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
