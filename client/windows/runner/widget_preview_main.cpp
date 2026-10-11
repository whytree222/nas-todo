#include <windows.h>
#include <objbase.h>

#include <cstdio>
#include <string>
#include <vector>

#include "desktop_widget.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

struct PreviewTask {
  const char* id;
  const char* title;
  bool completed;
  int priority;
};

LRESULT CALLBACK BackdropWindowProc(HWND window, UINT message, WPARAM wp,
                                    LPARAM lp) {
  if (message == WM_ERASEBKGND) return 1;
  if (message != WM_PAINT) return DefWindowProcW(window, message, wp, lp);
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(window, &paint);
  RECT client{};
  GetClientRect(window, &client);
  const int dpi = static_cast<int>(GetDpiForWindow(window));
  const int stripe = MulDiv(12, dpi > 0 ? dpi : 96, 96);
  const int warm_bottom = MulDiv(210, dpi > 0 ? dpi : 96, 96);
  const int cool_bottom = MulDiv(440, dpi > 0 ? dpi : 96, 96);
  const COLORREF colors[3][2] = {
      {RGB(229, 118, 129), RGB(253, 209, 185)},
      {RGB(74, 147, 206), RGB(182, 218, 244)},
      {RGB(112, 179, 168), RGB(215, 235, 214)},
  };
  const LONG tops[3] = {0, warm_bottom, cool_bottom};
  const LONG bottoms[3] = {warm_bottom, cool_bottom, client.bottom};
  for (int band = 0; band < 3; ++band) {
    for (LONG x = 0; x < client.right; x += stripe) {
      HBRUSH brush = CreateSolidBrush(colors[band][(x / stripe) % 2]);
      RECT block{x, tops[band], x + stripe, bottoms[band]};
      FillRect(dc, &block, brush);
      DeleteObject(brush);
    }
  }
  EndPaint(window, &paint);
  return 0;
}

// The backdrop remains owned by this harness and is destroyed after the widget.
// It provides visible blur input without reading wallpaper or other app windows.
struct PatternBackdrop {
  HWND window = nullptr;
  ~PatternBackdrop() {
    if (window && IsWindow(window)) DestroyWindow(window);
  }
  bool Create() {
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = BackdropWindowProc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = L"PRIVATE_TODO_SYNTHETIC_BACKDROP";
    if (!RegisterClassW(&window_class) &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
    window = CreateWindowExW(
        WS_EX_TOOLWINDOW, window_class.lpszClassName,
        L"Private Todo · Synthetic Preview Backdrop", WS_POPUP,
        20, 20, 1000, 1000, nullptr, nullptr, window_class.hInstance, nullptr);
    if (!window) return false;
    SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    UpdateWindow(window);
    return true;
  }
};

std::string Today() {
  SYSTEMTIME local{};
  GetLocalTime(&local);
  char date[11]{};
  sprintf_s(date, "%04u-%02u-%02u", static_cast<unsigned>(local.wYear),
            static_cast<unsigned>(local.wMonth),
            static_cast<unsigned>(local.wDay));
  return date;
}

EncodableMap State(const std::vector<PreviewTask>& tasks, const std::string& theme) {
  const std::string date = Today();
  EncodableList rows;
  for (const auto& task : tasks) {
    rows.emplace_back(EncodableMap{
        {EncodableValue("id"), EncodableValue(task.id)},
        {EncodableValue("title"), EncodableValue(task.title)},
        {EncodableValue("completed"), EncodableValue(task.completed)},
        {EncodableValue("due_date"), EncodableValue(date)},
        {EncodableValue("priority"), EncodableValue(task.priority)},
        {EncodableValue("conflict"), EncodableValue(false)},
    });
  }
  return EncodableMap{
      {EncodableValue("today"), EncodableValue(date)},
      {EncodableValue("editing"), EncodableValue(false)},
      {EncodableValue("status"), EncodableValue("已同步")},
      {EncodableValue("error"), EncodableValue("")},
      {EncodableValue("theme"), EncodableValue(theme)},
      {EncodableValue("tasks"), EncodableValue(rows)},
  };
}

void PumpPendingMessages() {
  MSG message{};
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    if (message.message == WM_QUIT) return;
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  GdiFlush();
}

bool Export(DesktopWidget& widget, const std::wstring& path) {
  PumpPendingMessages();
  const bool success = widget.ExportImage(path.c_str());
  std::printf("Widget preview export: %s\n", success ? "OK" : "FAILED");
  return success;
}

}  // namespace

// This executable uses synthetic tasks and does not open the app's data files,
// preferences, credentials, Flutter engine, or network connections.
int wmain(int argc, wchar_t** argv) {
  SetConsoleOutputCP(CP_UTF8);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(initialized)) {
    std::printf("Widget preview: COM initialization failed\n");
    return 3;
  }
  struct ComScope {
    ~ComScope() { CoUninitialize(); }
  } com_scope;

  bool export_image = false;
  bool live_export = false;
  bool self_test = false;
  bool pattern_backdrop = false;
  std::string theme = "green";
  std::wstring path = L"preview-widget.png";
  for (int i = 1; i < argc; ++i) {
    const std::wstring argument = argv[i];
    if (argument == L"--self-test") {
      self_test = true;
    } else if (argument == L"--pattern-backdrop") {
      pattern_backdrop = true;
    } else if (argument == L"--theme" && i + 1 < argc) {
      const std::wstring value = argv[++i];
      if (value == L"black") theme = "black";
      else if (value == L"white") theme = "white";
      else if (value == L"green") theme = "green";
      else if (value == L"blue") theme = "blue";
      else {
        std::printf("Widget preview: theme must be black, white, green, or blue\n");
        return 2;
      }
    } else if (argument == L"--export" || argument == L"--live-export") {
      export_image = true;
      live_export = argument == L"--live-export";
      if (i + 1 < argc && std::wstring(argv[i + 1]).rfind(L"--", 0) != 0) {
        path = argv[++i];
      }
    } else {
      std::printf("Usage: widget_preview [--self-test] [--export [PNG path]] "
                  "[--live-export [PNG path]] [--pattern-backdrop] "
                  "[--theme black|white|green|blue]\n");
      return 2;
    }
  }
  if (self_test) {
    const int result = DesktopWidget::SelfTest();
    std::printf("Widget native self-test: %s (%d)\n",
                result == 0 ? "OK" : "FAILED", result);
    return result;
  }

  PatternBackdrop backdrop;
  if (pattern_backdrop && !backdrop.Create()) {
    std::printf("Widget preview: backdrop creation failed\n");
    return 8;
  }
  std::vector<PreviewTask> tasks = {
      {"preview-plan", "整理本周计划", false, 2},
      {"preview-read", "阅读 20 分钟", false, 0},
      {"preview-plant", "给绿植浇水", true, 0},
      {"preview-walk", "散步，放空一下", false, 0},
  };
  DesktopWidget* active_widget = nullptr;
  DesktopWidget widget(
      [&](const std::string& id, bool completed) {
        for (auto& task : tasks) {
          if (id == task.id) task.completed = completed;
        }
        if (active_widget) active_widget->Update(State(tasks, theme));
      },
      []() { std::printf("Widget preview: open application\n"); },
      [&]() {
        if (active_widget) active_widget->Update(State(tasks, theme));
        std::printf("Widget preview: sync\n");
      },
      []() { PostQuitMessage(0); });
  active_widget = &widget;
  widget.Update(State(tasks, theme));
  if (!widget.Create(false)) {
    std::printf("Widget preview: window creation failed\n");
    return 4;
  }
  widget.Update(State(tasks, theme));

  if (pattern_backdrop) {
    const HWND native = FindWindowW(L"CN_PRIVATE_TODO_DESKTOP_WIDGET", nullptr);
    SetForegroundWindow(native);
    std::printf("Widget preview: active=%d\n", GetForegroundWindow() == native ? 1 : 0);
  }

  if (export_image && !live_export) {
    return Export(widget, path) ? 0 : 5;
  }
  const UINT_PTR export_timer =
      live_export ? SetTimer(nullptr, 0, 1000, nullptr) : 0;
  if (live_export && export_timer == 0) {
    std::printf("Widget preview: export timer creation failed\n");
    return 6;
  }
  std::printf("Widget preview: %s\n",
              live_export ? "waiting to export" : "ready");
  MSG message{};
  int message_result = 0;
  while ((message_result = GetMessageW(&message, nullptr, 0, 0)) > 0) {
    if (live_export && message.hwnd == nullptr &&
        message.message == WM_TIMER && message.wParam == export_timer) {
      KillTimer(nullptr, export_timer);
      return Export(widget, path) ? 0 : 5;
    }
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  if (export_timer != 0) KillTimer(nullptr, export_timer);
  std::printf("Widget preview: closed\n");
  return message_result == -1 ? 7 : 0;
}
