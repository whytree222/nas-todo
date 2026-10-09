#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  auto arguments = GetCommandLineArguments();
  if (std::find(arguments.begin(), arguments.end(), "--widget-self-test") != arguments.end()) {
    AttachConsole(ATTACH_PARENT_PROCESS);
    return DesktopWidget::SelfTest();
  }
  const bool widget_only = std::find(arguments.begin(), arguments.end(), "--widget") != arguments.end();
  const bool host_self_test = std::find(arguments.begin(), arguments.end(), "--widget-host-self-test") != arguments.end();
  // One engine owns the offline queue. A second launch reuses its windows.
  HANDLE singleton = CreateMutex(nullptr, FALSE, L"Local\\cn.privatetodo.app.instance");
  if (!singleton) return EXIT_FAILURE;
  if (singleton && GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = FindWindow(L"CN_PRIVATE_TODO_WINDOW", nullptr);
    if (existing) {
      if (widget_only) PostMessage(existing, FlutterWindow::kOpenWidget, 0, 0);
      else { ShowWindow(existing, SW_RESTORE); SetForegroundWindow(existing); }
    }
    CloseHandle(singleton);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, widget_only, host_self_test);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"私有待办", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (singleton) CloseHandle(singleton);
  return static_cast<int>(msg.wParam);
}
