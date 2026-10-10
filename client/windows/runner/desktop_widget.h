#ifndef PRIVATE_TODO_DESKTOP_WIDGET_H_
#define PRIVATE_TODO_DESKTOP_WIDGET_H_

#include <windows.h>
#include <flutter/encodable_value.h>
#include <functional>
#include <string>
#include <vector>
#include <memory>
#include "widget_painter.h"
class GlassSurface;

class DesktopWidget {
 public:
  using Toggle = std::function<void(const std::string&, bool)>;
  DesktopWidget(Toggle toggle, std::function<void()> open_main,
                std::function<void()> sync, std::function<void()> closed);
  ~DesktopWidget();
  bool Create(bool load_settings = true);
  void Update(const flutter::EncodableMap& state);
  void Reveal();
  bool IsOpen() const { return hwnd_ && IsWindow(hwnd_); }
  static int SelfTest();
  bool ExportImage(const wchar_t* path);

 private:
  struct Task {
    std::string id;
    std::wstring title;
    std::string date;
    bool completed = false;
    bool conflict = false;
    int priority = 0;
  };
  enum class Edge { none, left, right, top, bottom };
  HWND hwnd_ = nullptr;
  Toggle toggle_;
  std::function<void()> open_main_, sync_, closed_;
  std::vector<Task> tasks_;
  std::vector<std::pair<RECT, Task>> hits_;
  std::wstring status_ = L"正在读取待办";
  std::wstring error_;
  std::string today_;
  bool editing_ = false, pinned_ = true, auto_hide_ = true;
  bool menu_hover_ = false, menu_open_ = false, painted_ = false;
  bool collapsed_ = false, dragging_ = false, transition_ = false, save_settings_ = true;
  Edge edge_ = Edge::none;
  RECT expanded_{};
  size_t offset_ = 0;
  ULONGLONG outside_since_ = 0;
  UINT current_dpi_ = 96;
  WidgetPaintLayout layout_;
  std::unique_ptr<GlassSurface> surface_;
  int Dp(int value) const;
  RECT WorkArea() const;
  void Snap();
  void Collapse();
  void Poll(POINT cursor, ULONGLONG now);
  void Save();
  void Paint();
  void ShowMenu();
  WidgetPaintInput PaintState() const;
  std::vector<Task> VisibleTasks() const;
  LRESULT Message(UINT message, WPARAM wp, LPARAM lp);
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp);
};

#endif
