#include "desktop_widget.h"
#include <algorithm>
#include <cstdio>
#include <windowsx.h>

namespace {
constexpr wchar_t kClass[] = L"CN_PRIVATE_TODO_DESKTOP_WIDGET";
constexpr wchar_t kSettings[] = L"Software\\PrivateTodo\\DesktopWidget";
constexpr COLORREF kClear = RGB(1, 2, 3);
std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int count = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(static_cast<size_t>(count), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), count);
  return result;
}
const flutter::EncodableValue* Field(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}
std::string String(const flutter::EncodableMap& map, const char* key) {
  auto* value = Field(map, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? *text : "";
}
bool Bool(const flutter::EncodableMap& map, const char* key) {
  auto* value = Field(map, key);
  const auto* flag = value ? std::get_if<bool>(value) : nullptr;
  return flag && *flag;
}
DWORD Setting(const wchar_t* name, DWORD fallback) {
  DWORD value = fallback, bytes = sizeof(value);
  RegGetValue(HKEY_CURRENT_USER, kSettings, name, RRF_RT_REG_DWORD, nullptr, &value, &bytes);
  return value;
}
void Put(HKEY key, const wchar_t* name, DWORD value) {
  RegSetValueEx(key, name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value), sizeof(value));
}
}

DesktopWidget::DesktopWidget(Toggle toggle, std::function<void()> open_main,
    std::function<void()> sync, std::function<void()> closed)
    : toggle_(std::move(toggle)), open_main_(std::move(open_main)),
      sync_(std::move(sync)), closed_(std::move(closed)) {}
DesktopWidget::~DesktopWidget() { if (IsOpen()) DestroyWindow(hwnd_); }

int DesktopWidget::Dp(int value) const {
  const UINT dpi = hwnd_ ? GetDpiForWindow(hwnd_) : 96;
  return MulDiv(value, static_cast<int>(dpi ? dpi : 96), 96);
}

bool DesktopWidget::Create(bool load_settings) {
  save_settings_ = load_settings;
  WNDCLASS cls{};
  cls.hInstance = GetModuleHandle(nullptr);
  cls.lpszClassName = kClass;
  cls.lpfnWndProc = WndProc;
  cls.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClass(&cls);
  const int x = load_settings ? static_cast<int>(Setting(L"X", 40)) : 40;
  const int y = load_settings ? static_cast<int>(Setting(L"Y", 40)) : 40;
  const int width = load_settings ? static_cast<int>(Setting(L"Width", 350)) : 350;
  const int height = load_settings ? static_cast<int>(Setting(L"Height", 440)) : 440;
  pinned_ = !load_settings || Setting(L"Pinned", 1) != 0;
  auto_hide_ = !load_settings || Setting(L"AutoHide", 1) != 0;
  hwnd_ = CreateWindowEx(WS_EX_LAYERED | WS_EX_TOOLWINDOW,
      kClass, L"私有待办 · 桌面组件", WS_POPUP,
      x, y, std::clamp(width, 300, 800), std::clamp(height, 240, 1000),
      nullptr, nullptr, cls.hInstance, this);
  if (!hwnd_) return false;
  if (!SetLayeredWindowAttributes(hwnd_, kClear, 255, LWA_COLORKEY)) return false;
  Snap();
  SetWindowPos(hwnd_, pinned_ ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  SetTimer(hwnd_, 1, 100, nullptr);
  return true;
}

RECT DesktopWidget::WorkArea() const {
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  GetMonitorInfo(MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST), &monitor);
  return monitor.rcWork;
}

void DesktopWidget::Snap() {
  if (!IsOpen() || collapsed_) return;
  RECT rect{};
  GetWindowRect(hwnd_, &rect);
  const RECT work = WorkArea();
  const LONG width = std::min(rect.right - rect.left, work.right - work.left);
  const LONG height = std::min(rect.bottom - rect.top, work.bottom - work.top);
  rect.left = std::clamp(rect.left, work.left, work.right - width);
  rect.top = std::clamp(rect.top, work.top, work.bottom - height);
  rect.right = rect.left + width;
  rect.bottom = rect.top + height;
  const LONG distances[] = {rect.left - work.left, work.right - rect.right,
      rect.top - work.top, work.bottom - rect.bottom};
  const auto nearest = std::min_element(std::begin(distances), std::end(distances));
  edge_ = Edge::none;
  if (*nearest <= Dp(18)) {
    edge_ = static_cast<Edge>(1 + (nearest - distances));
    if (edge_ == Edge::left) rect.left = work.left;
    if (edge_ == Edge::right) rect.left = work.right - width;
    if (edge_ == Edge::top) rect.top = work.top;
    if (edge_ == Edge::bottom) rect.top = work.bottom - height;
  }
  expanded_ = {rect.left, rect.top, rect.left + width, rect.top + height};
  transition_ = true;
  SetWindowPos(hwnd_, nullptr, rect.left, rect.top, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
  transition_ = false;
  outside_since_ = 0;
}

void DesktopWidget::Collapse() {
  if (collapsed_ || edge_ == Edge::none || !auto_hide_ || dragging_) return;
  const RECT work = WorkArea();
  int x = expanded_.left, y = expanded_.top;
  int width = Dp(20), height = Dp(90);
  if (edge_ == Edge::left || edge_ == Edge::right) {
    x = edge_ == Edge::left ? work.left : work.right - width;
    y = std::clamp(expanded_.top + (expanded_.bottom - expanded_.top - height) / 2, work.top, work.bottom - height);
  } else {
    std::swap(width, height);
    x = std::clamp(expanded_.left + (expanded_.right - expanded_.left - width) / 2, work.left, work.right - width);
    y = edge_ == Edge::top ? work.top : work.bottom - height;
  }
  collapsed_ = true;
  transition_ = true;
  SetWindowPos(hwnd_, nullptr, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
  transition_ = false;
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void DesktopWidget::Reveal() {
  if (!IsOpen()) return;
  if (collapsed_) {
    collapsed_ = false;
    transition_ = true;
    SetWindowPos(hwnd_, nullptr, expanded_.left, expanded_.top,
        expanded_.right - expanded_.left, expanded_.bottom - expanded_.top,
        SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    transition_ = false;
    InvalidateRect(hwnd_, nullptr, TRUE);
  }
  outside_since_ = 0;
}

void DesktopWidget::Poll(POINT cursor, ULONGLONG now) {
  if (!IsOpen() || dragging_) return;
  RECT bounds{};
  GetWindowRect(hwnd_, &bounds);
  if (PtInRect(&bounds, cursor)) { Reveal(); outside_since_ = 0; }
  else if (!collapsed_ && auto_hide_ && edge_ != Edge::none) {
    if (!outside_since_) outside_since_ = now;
    else if (now - outside_since_ >= 900) Collapse();
  }
}

void DesktopWidget::Save() {
  if (!save_settings_) return;
  HKEY key;
  if (RegCreateKeyEx(HKEY_CURRENT_USER, kSettings, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) return;
  const RECT rect = expanded_;
  Put(key, L"X", static_cast<DWORD>(rect.left));
  Put(key, L"Y", static_cast<DWORD>(rect.top));
  Put(key, L"Width", static_cast<DWORD>(rect.right - rect.left));
  Put(key, L"Height", static_cast<DWORD>(rect.bottom - rect.top));
  Put(key, L"Pinned", pinned_ ? 1 : 0);
  Put(key, L"AutoHide", auto_hide_ ? 1 : 0);
  RegCloseKey(key);
}

void DesktopWidget::Update(const flutter::EncodableMap& state) {
  today_ = String(state, "today");
  status_ = Wide(String(state, "status"));
  error_ = Wide(String(state, "error"));
  editing_ = Bool(state, "editing");
  tasks_.clear();
  const auto* value = Field(state, "tasks");
  const auto* tasks = value ? std::get_if<flutter::EncodableList>(value) : nullptr;
  if (tasks) for (const auto& entry : *tasks) {
    const auto* map = std::get_if<flutter::EncodableMap>(&entry);
    if (!map) continue;
    Task task;
    task.id = String(*map, "id");
    task.title = Wide(String(*map, "title"));
    task.date = String(*map, "due_date");
    task.completed = Bool(*map, "completed");
    task.conflict = Bool(*map, "conflict");
    const auto* priority = Field(*map, "priority");
    if (priority) {
      if (const auto* number = std::get_if<int32_t>(priority)) task.priority = *number;
    }
    tasks_.push_back(std::move(task));
  }
  if (IsOpen()) InvalidateRect(hwnd_, nullptr, TRUE);
}

std::vector<DesktopWidget::Task> DesktopWidget::VisibleTasks() const {
  std::vector<Task> result;
  for (const auto& task : tasks_) {
    if (task.date == (undated_ ? "" : today_)) result.push_back(task);
  }
  std::sort(result.begin(), result.end(), [](const Task& a, const Task& b) {
    if (a.completed != b.completed) return !a.completed;
    if (a.priority != b.priority) return a.priority > b.priority;
    return a.title < b.title;
  });
  return result;
}

void DesktopWidget::Paint() {
  PAINTSTRUCT paint{};
  HDC dc = BeginPaint(hwnd_, &paint);
  RECT bounds{};
  GetClientRect(hwnd_, &bounds);
  HDC buffer = CreateCompatibleDC(dc);
  HBITMAP bitmap = CreateCompatibleBitmap(dc, bounds.right, bounds.bottom);
  HGDIOBJ previous_bitmap = SelectObject(buffer, bitmap);
  HBRUSH clear = CreateSolidBrush(kClear);
  FillRect(buffer, &bounds, clear);
  DeleteObject(clear);
  SetBkMode(buffer, TRANSPARENT);
  const auto text = [&](const std::wstring& value, RECT rect, int height, bool strike = false) {
    HFONT font = CreateFont(-Dp(height), 0, 0, 0, FW_NORMAL, FALSE, strike ? TRUE : FALSE,
        FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
        DEFAULT_PITCH, L"Microsoft YaHei");
    HGDIOBJ old = SelectObject(buffer, font);
    RECT shadow = rect;
    OffsetRect(&shadow, Dp(1), Dp(1));
    SetTextColor(buffer, RGB(12, 20, 16));
    DrawText(buffer, value.c_str(), -1, &shadow, DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
    SetTextColor(buffer, strike ? RGB(180, 202, 190) : RGB(246, 255, 249));
    DrawText(buffer, value.c_str(), -1, &rect, DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
    SelectObject(buffer, old);
    DeleteObject(font);
  };
  const auto button = [&](const wchar_t* label, RECT rect, bool active = false) {
    HBRUSH brush = CreateSolidBrush(active ? RGB(46, 112, 83) : RGB(35, 49, 43));
    FillRect(buffer, &rect, brush);
    DeleteObject(brush);
    RECT inset = rect; inset.left += Dp(4);
    text(label, inset, 12);
  };
  hits_.clear();
  if (collapsed_) {
    button(edge_ == Edge::left ? L">" : edge_ == Edge::right ? L"<" : L"待办", bounds, true);
  } else {
    const int width = bounds.right;
    const int height = bounds.bottom;
    const RECT title{Dp(12), Dp(8), width - Dp(144), Dp(42)};
    button(L"私有待办 · 拖动", title);
    button(L"主界面", {width - Dp(138), Dp(8), width - Dp(72), Dp(42)});
    button(pinned_ ? L"钉" : L"浮", {width - Dp(66), Dp(8), width - Dp(38), Dp(42)}, pinned_);
    button(L"×", {width - Dp(32), Dp(8), width - Dp(6), Dp(42)});
    button(L"今天", {Dp(12), Dp(50), Dp(60), Dp(78)}, !undated_);
    button(L"未安排", {Dp(66), Dp(50), Dp(126), Dp(78)}, undated_);
    button(auto_hide_ ? L"贴边隐藏 ✓" : L"贴边隐藏", {width - Dp(116), Dp(50), width - Dp(12), Dp(78)}, auto_hide_);
    const auto tasks = VisibleTasks();
    const size_t count = static_cast<size_t>(std::max(1, (height - Dp(130)) / Dp(48)));
    if (!tasks.empty()) offset_ = std::min(offset_, tasks.size() - 1); else offset_ = 0;
    for (size_t i = offset_; i < tasks.size() && i < offset_ + count; ++i) {
      const int y = Dp(90) + static_cast<int>(i - offset_) * Dp(48);
      const RECT check{Dp(12), y + Dp(6), Dp(38), y + Dp(34)};
      button(tasks[i].conflict ? L"!" : tasks[i].completed ? L"✓" : L"□", check, tasks[i].completed);
      text(tasks[i].title, {Dp(48), y, width - Dp(12), y + Dp(42)}, 14, tasks[i].completed);
      hits_.push_back({check, tasks[i]});
    }
    if (tasks.empty()) text(L"暂时没有待办", {Dp(16), Dp(94), width - Dp(16), Dp(142)}, 14);
    std::wstring footer = error_.empty() ? status_ : error_;
    if (tasks.size() > count) footer += L" · 滚轮查看更多";
    text(footer, {Dp(12), height - Dp(36), width - Dp(64), height - Dp(6)}, 11);
    button(L"同步", {width - Dp(58), height - Dp(36), width - Dp(8), height - Dp(6)});
    HPEN pen = CreatePen(PS_SOLID, Dp(2), RGB(69, 118, 91));
    HGDIOBJ old_pen = SelectObject(buffer, pen);
    MoveToEx(buffer, width - Dp(16), height - Dp(3), nullptr);
    LineTo(buffer, width - Dp(3), height - Dp(16));
    SelectObject(buffer, old_pen); DeleteObject(pen);
  }
  BitBlt(dc, 0, 0, bounds.right, bounds.bottom, buffer, 0, 0, SRCCOPY);
  SelectObject(buffer, previous_bitmap);
  DeleteObject(bitmap); DeleteDC(buffer); EndPaint(hwnd_, &paint);
}

LRESULT DesktopWidget::Message(UINT message, WPARAM wp, LPARAM lp) {
  switch (message) {
    case WM_PAINT: Paint(); return 0;
    case WM_ERASEBKGND: return 1;
    case WM_TIMER: { POINT point{}; GetCursorPos(&point); Poll(point, GetTickCount64()); return 0; }
    case WM_ENTERSIZEMOVE: Reveal(); dragging_ = true; return 0;
    case WM_EXITSIZEMOVE: dragging_ = false; Snap(); Save(); return 0;
    case WM_SIZE: InvalidateRect(hwnd_, nullptr, TRUE); return 0;
    case WM_DISPLAYCHANGE: Reveal(); Snap(); return 0;
    case WM_DPICHANGED: {
      Reveal(); const auto* rect = reinterpret_cast<RECT*>(lp);
      SetWindowPos(hwnd_, nullptr, rect->left, rect->top, rect->right - rect->left,
          rect->bottom - rect->top, SWP_NOZORDER | SWP_NOACTIVATE); Snap(); return 0;
    }
    case WM_GETMINMAXINFO: {
      if (!transition_) {
        auto* limits = reinterpret_cast<MINMAXINFO*>(lp);
        limits->ptMinTrackSize = {Dp(300), Dp(240)};
      }
      return 0;
    }
    case WM_NCHITTEST: {
      if (collapsed_) return HTCLIENT;
      POINT point{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)}; ScreenToClient(hwnd_, &point);
      RECT rect{}; GetClientRect(hwnd_, &rect);
      if (point.x >= rect.right - Dp(18) && point.y >= rect.bottom - Dp(18)) return HTBOTTOMRIGHT;
      if (point.y >= Dp(8) && point.y < Dp(42) && point.x < rect.right - Dp(144)) return HTCAPTION;
      return HTCLIENT;
    }
    case WM_MOUSEWHEEL: {
      if (GET_WHEEL_DELTA_WPARAM(wp) < 0) ++offset_; else if (offset_ > 0) --offset_;
      InvalidateRect(hwnd_, nullptr, TRUE); return 0;
    }
    case WM_LBUTTONUP: {
      if (collapsed_) { Reveal(); return 0; }
      const int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
      RECT rect{}; GetClientRect(hwnd_, &rect);
      if (y >= Dp(8) && y < Dp(42)) {
        if (x >= rect.right - Dp(32)) PostMessage(hwnd_, WM_CLOSE, 0, 0);
        else if (x >= rect.right - Dp(66)) {
          pinned_ = !pinned_;
          SetWindowPos(hwnd_, pinned_ ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
              SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE); Save();
        } else if (x >= rect.right - Dp(138)) open_main_();
      } else if (y >= Dp(50) && y < Dp(78)) {
        if (x >= rect.right - Dp(116)) { auto_hide_ = !auto_hide_; Reveal(); Save(); }
        else if (x < Dp(126)) { undated_ = x >= Dp(66); offset_ = 0; }
      } else if (y >= rect.bottom - Dp(36) && x >= rect.right - Dp(58)) sync_();
      else if (!editing_) {
        const POINT point{x, y};
        for (const auto& hit : hits_) if (PtInRect(&hit.first, point)) {
          if (hit.second.conflict) open_main_(); else toggle_(hit.second.id, !hit.second.completed);
          break;
        }
      }
      InvalidateRect(hwnd_, nullptr, TRUE); return 0;
    }
    case WM_CLOSE: Save(); DestroyWindow(hwnd_); return 0;
    case WM_NCDESTROY: {
      const HWND old = hwnd_; hwnd_ = nullptr; KillTimer(old, 1);
      SetWindowLongPtr(old, GWLP_USERDATA, 0); closed_();
      return DefWindowProc(old, message, wp, lp);
    }
  }
  return DefWindowProc(hwnd_, message, wp, lp);
}

LRESULT CALLBACK DesktopWidget::WndProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCT*>(lp);
    auto* self = static_cast<DesktopWidget*>(create->lpCreateParams);
    self->hwnd_ = hwnd; SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  auto* self = reinterpret_cast<DesktopWidget*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  return self ? self->Message(message, wp, lp) : DefWindowProc(hwnd, message, wp, lp);
}

int DesktopWidget::SelfTest() {
  bool closed = false, toggled = false;
  DesktopWidget widget([&](const std::string& id, bool done) { toggled = id == "one" && done; },
      [] {}, [] {}, [&] { closed = true; });
  if (!widget.Create(false)) return 1;
  COLORREF key = 0; BYTE alpha = 0; DWORD flags = 0;
  if (!GetLayeredWindowAttributes(widget.hwnd_, &key, &alpha, &flags) || key != kClear || !(flags & LWA_COLORKEY)) return 2;
  if (GetWindow(widget.hwnd_, GW_OWNER) || (GetWindowLongPtr(widget.hwnd_, GWL_STYLE) & WS_CHILD)) return 3;
  using flutter::EncodableValue;
  flutter::EncodableMap task{{EncodableValue("id"), EncodableValue("one")},
      {EncodableValue("title"), EncodableValue("桌面测试任务")},
      {EncodableValue("due_date"), EncodableValue("2026-10-09")},
      {EncodableValue("completed"), EncodableValue(false)}};
  widget.Update({{EncodableValue("today"), EncodableValue("2026-10-09")},
      {EncodableValue("tasks"), EncodableValue(flutter::EncodableList{EncodableValue(task)})}});
  UpdateWindow(widget.hwnd_);
  if (widget.hits_.empty()) return 4;
  SendMessage(widget.hwnd_, WM_LBUTTONUP, 0, MAKELPARAM(widget.Dp(22), widget.Dp(110)));
  if (!toggled) return 5;
  const RECT work = widget.WorkArea();
  for (const Edge edge : {Edge::left, Edge::right, Edge::top, Edge::bottom}) {
    widget.edge_ = edge;
    widget.expanded_ = {work.left, work.top, work.left + widget.Dp(320), work.top + widget.Dp(300)};
    if (edge == Edge::right) OffsetRect(&widget.expanded_, work.right - widget.expanded_.right, 0);
    if (edge == Edge::bottom) OffsetRect(&widget.expanded_, 0, work.bottom - widget.expanded_.bottom);
    widget.outside_since_ = 100;
    widget.Poll({work.right + 10, work.bottom + 10}, 1100);
    if (!widget.collapsed_) return 6;
    RECT tab{}; GetWindowRect(widget.hwnd_, &tab);
    if (tab.left < work.left || tab.top < work.top || tab.right > work.right || tab.bottom > work.bottom) return 7;
    widget.Poll({tab.left + 2, tab.top + 2}, 1200);
    if (widget.collapsed_) return 8;
  }
  // Hiding a main-style window must not hide this unowned component.
  HWND main = CreateWindow(L"STATIC", L"host", WS_OVERLAPPEDWINDOW, 0, 0, 100, 100, nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
  ShowWindow(main, SW_HIDE);
  if (!IsWindowVisible(widget.hwnd_)) return 9;
  DestroyWindow(main);
  SendMessage(widget.hwnd_, WM_CLOSE, 0, 0);
  if (!closed || widget.IsOpen()) return 10;
  std::puts("Native widget checks passed: transparency, independent lifetime, checkbox, four-edge collapse, hover reveal");
  return 0;
}
