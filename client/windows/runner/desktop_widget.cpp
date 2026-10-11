#include "desktop_widget.h"
#include <algorithm>
#include <cstdio>
#include <windowsx.h>
#include <gdiplus.h>
#include <dwmapi.h>
#include "glass_surface.h"

namespace {
constexpr wchar_t kClass[] = L"CN_PRIVATE_TODO_DESKTOP_WIDGET";
constexpr wchar_t kSettings[] = L"Software\\PrivateTodo\\DesktopWidget";

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

bool VerifyPalettePixels() {
  if (ParseWidgetTheme("black") != WidgetTheme::black ||
      ParseWidgetTheme("white") != WidgetTheme::white ||
      ParseWidgetTheme("blue") != WidgetTheme::blue ||
      ParseWidgetTheme("green") != WidgetTheme::green ||
      ParseWidgetTheme("unknown") != WidgetTheme::green ||
      ParseWidgetTheme("") != WidgetTheme::green) return false;
  WidgetPaintInput input;
  input.width = 340; input.height = 320; input.native_glass = false;
  input.today = L"2026-10-10";
  input.tasks = {{L"未完成", false, false, 0}, {L"已完成", true, false, 0}};
  BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = input.width; info.bmiHeader.biHeight = -input.height;
  info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
  HDC dc = CreateCompatibleDC(nullptr); void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!bitmap || !bits) { if (bitmap) DeleteObject(bitmap); DeleteDC(dc); return false; }
  const auto previous = SelectObject(dc, bitmap);
  bool valid = true; RECT first_check{};
  for (const auto theme : {WidgetTheme::green, WidgetTheme::black,
                           WidgetTheme::white, WidgetTheme::blue}) {
    input.theme = theme;
    const auto layout = PaintWidget(dc, input);
    if (!layout.painted || layout.tasks.size() != 2) { valid = false; break; }
    if (theme == WidgetTheme::green) first_check = layout.tasks.front().checkbox;
    else if (!EqualRect(&first_check, &layout.tasks.front().checkbox)) { valid = false; break; }
    const auto* bytes = static_cast<const BYTE*>(bits);
    if (bytes[3] != 0) { valid = false; break; }
    for (int i = 0; i < input.width * input.height; ++i) {
      const BYTE* pixel = bytes + static_cast<size_t>(i) * 4;
      if (pixel[0] > pixel[3] || pixel[1] > pixel[3] || pixel[2] > pixel[3]) {
        valid = false; break;
      }
    }
    // This unobstructed body pixel must distinguish light and tinted themes.
    const BYTE* body = bytes + (static_cast<size_t>(96) * input.width + 170) * 4;
    if (theme == WidgetTheme::white && !(body[0] > 210 && body[1] > 210 && body[2] > 210)) valid = false;
    if (theme == WidgetTheme::black && !(body[0] < 50 && body[1] < 50 && body[2] < 50)) valid = false;
    if (theme == WidgetTheme::green && !(body[1] > body[0] && body[1] > body[2])) valid = false;
    if (theme == WidgetTheme::blue && !(body[0] > body[1] && body[1] > body[2])) valid = false;
    if (!valid) break;
  }
  SelectObject(dc, previous); DeleteObject(bitmap); DeleteDC(dc);
  return valid;
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
  const int saved_width = load_settings ? static_cast<int>(Setting(L"Width", 0)) : 0;
  const int saved_height = load_settings ? static_cast<int>(Setting(L"Height", 0)) : 0;
  const int width = saved_width > 0 ? saved_width : 340;
  const int height = saved_height > 0 ? saved_height : 420;
  pinned_ = !load_settings || Setting(L"Pinned", 1) != 0;
  auto_hide_ = !load_settings || Setting(L"AutoHide", 1) != 0;
  hwnd_ = CreateWindowEx(WS_EX_NOREDIRECTIONBITMAP | WS_EX_TOOLWINDOW,
      kClass, L"私有待办 · 桌面组件", WS_POPUP | WS_THICKFRAME,
      x, y, std::clamp(width, 300, 800), std::clamp(height, 240, 1000),
      nullptr, nullptr, cls.hInstance, this);
  if (!hwnd_) return false;
  current_dpi_ = GetDpiForWindow(hwnd_);
  surface_ = std::make_unique<GlassSurface>();
  if (!surface_->Create(hwnd_)) return false;
  ApplyTheme();
  // Stored sizes are physical pixels; keep controls usable after a DPI change.
  SetWindowPos(hwnd_, nullptr, 0, 0,
      saved_width > 0 ? std::max(width, Dp(300)) : Dp(340),
      saved_height > 0 ? std::max(height, Dp(240)) : Dp(420),
      SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
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
  if (!IsOpen() || dragging_ || menu_open_) return;
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

void DesktopWidget::ApplyTheme() {
  if (!IsOpen()) return;
  const BOOL dark = theme_ == WidgetTheme::white ? FALSE : TRUE;
  DwmSetWindowAttribute(hwnd_, static_cast<DWMWINDOWATTRIBUTE>(20),
                        &dark, sizeof(dark));
}

void DesktopWidget::Update(const flutter::EncodableMap& state) {
  const WidgetTheme previous_theme = theme_;
  theme_ = ParseWidgetTheme(String(state, "theme"));
  if (theme_ != previous_theme) ApplyTheme();
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
    if (task.date.empty() || task.date == today_) result.push_back(task);
  }
  std::sort(result.begin(), result.end(), [](const Task& a, const Task& b) {
    if (a.completed != b.completed) return !a.completed;
    if (a.priority != b.priority) return a.priority > b.priority;
    return a.title < b.title;
  });
  return result;
}

WidgetPaintInput DesktopWidget::PaintState() const {
  RECT rect{}; GetClientRect(hwnd_, &rect);
  WidgetPaintInput state;
  state.width = rect.right; state.height = rect.bottom;
  state.dpi = GetDpiForWindow(hwnd_); state.collapsed = collapsed_;
  state.edge = static_cast<WidgetEdge>(edge_);
  state.theme = theme_;
  state.native_glass = surface_ && surface_->NativeBackdrop();
  state.editing = editing_; state.menu_hover = menu_hover_; state.has_error = !error_.empty();
  state.today = Wide(today_); state.offset = offset_;
  for (const auto& task : VisibleTasks()) state.tasks.push_back({task.title, task.completed, task.conflict, task.priority});
  return state;
}

void DesktopWidget::Paint() {
  PAINTSTRUCT paint{}; BeginPaint(hwnd_, &paint);
  const auto input = PaintState();
  if (input.width > 0 && input.height > 0 && surface_) {
    BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = input.width; info.bmiHeader.biHeight = -input.height;
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
    HDC dc = CreateCompatibleDC(nullptr); void* pixels = nullptr;
    HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
    if (bitmap && pixels) {
      const auto old = SelectObject(dc, bitmap);
      layout_ = PaintWidget(dc, input); offset_ = layout_.offset;
      hits_.clear(); const auto tasks = VisibleTasks();
      for (const auto& hit : layout_.tasks) hits_.push_back({hit.checkbox, tasks[hit.task_index]});
      painted_ = layout_.painted && surface_->Present(input.width, input.height, pixels, static_cast<UINT>(input.width * 4));
      SelectObject(dc, old); DeleteObject(bitmap);
    }
    DeleteDC(dc);
  }
  EndPaint(hwnd_, &paint);
}

void DesktopWidget::ShowMenu() {
  menu_open_ = true; Reveal();
  HMENU menu = CreatePopupMenu();
  AppendMenu(menu, MF_STRING, 1, L"打开主界面");
  AppendMenu(menu, MF_STRING, 2, L"立即同步");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING | (pinned_ ? MF_CHECKED : 0), 3, L"保持置顶");
  AppendMenu(menu, MF_STRING | (auto_hide_ ? MF_CHECKED : 0), 4, L"贴边自动收起");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, 5, L"关闭组件");
  POINT position{layout_.menu.right, layout_.menu.bottom + Dp(6)};
  ClientToScreen(hwnd_, &position); SetForegroundWindow(hwnd_);
  const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTALIGN,
      position.x, position.y, 0, hwnd_, nullptr);
  DestroyMenu(menu); menu_open_ = false; outside_since_ = 0;
  if (command == 1) open_main_();
  if (command == 2) sync_();
  if (command == 3) { pinned_ = !pinned_; SetWindowPos(hwnd_, pinned_ ? HWND_TOPMOST : HWND_NOTOPMOST,
      0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE); Save(); }
  if (command == 4) { auto_hide_ = !auto_hide_; Save(); }
  if (command == 5) PostMessage(hwnd_, WM_CLOSE, 0, 0);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

bool DesktopWidget::ExportImage(const wchar_t* path) {
  if (!IsOpen()) return false;
  UpdateWindow(hwnd_); DwmFlush();
  RECT rect{}; GetWindowRect(hwnd_, &rect);
  const int width = rect.right - rect.left, height = rect.bottom - rect.top;
  BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
  HDC desktop = GetDC(nullptr), dc = CreateCompatibleDC(desktop); void* pixels = nullptr;
  HBITMAP bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  if (!bitmap || !pixels) { if (bitmap) DeleteObject(bitmap); DeleteDC(dc); ReleaseDC(nullptr, desktop); return false; }
  const auto old = SelectObject(dc, bitmap);
  const bool captured = BitBlt(dc, 0, 0, width, height, desktop, rect.left, rect.top, SRCCOPY | CAPTUREBLT) != FALSE;
  GdiFlush();
  auto* bytes = static_cast<BYTE*>(pixels);
  for (size_t i = 3; i < static_cast<size_t>(width) * height * 4; i += 4) bytes[i] = 255;
  bool saved = false;
  if (captured) {
    Gdiplus::Bitmap image(width, height, width * 4, PixelFormat32bppARGB, bytes);
    UINT count = 0, size = 0; Gdiplus::GetImageEncodersSize(&count, &size);
    std::vector<BYTE> codecs(size);
    if (size && Gdiplus::GetImageEncoders(count, size, reinterpret_cast<Gdiplus::ImageCodecInfo*>(codecs.data())) == Gdiplus::Ok) {
      const auto* encoders = reinterpret_cast<const Gdiplus::ImageCodecInfo*>(codecs.data());
      for (UINT i = 0; i < count; ++i) if (std::wcscmp(encoders[i].MimeType, L"image/png") == 0)
        saved = image.Save(path, &encoders[i].Clsid, nullptr) == Gdiplus::Ok;
    }
  }
  SelectObject(dc, old); DeleteObject(bitmap); DeleteDC(dc); ReleaseDC(nullptr, desktop);
  return saved;
}

LRESULT DesktopWidget::Message(UINT message, WPARAM wp, LPARAM lp) {
  switch (message) {
    case WM_NCCALCSIZE: return 0;
    case WM_PAINT: Paint(); return 0;
    case WM_ERASEBKGND: return 1;
    case WM_TIMER: { POINT point{}; GetCursorPos(&point); Poll(point, GetTickCount64()); return 0; }
    case WM_ENTERSIZEMOVE: Reveal(); dragging_ = true; return 0;
    case WM_EXITSIZEMOVE: dragging_ = false; Snap(); Save(); return 0;
    case WM_SIZE: InvalidateRect(hwnd_, nullptr, TRUE); return 0;
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE: Reveal(); Snap(); return 0;
    case WM_DPICHANGED: {
      const auto* rect = reinterpret_cast<RECT*>(lp);
      const UINT new_dpi = HIWORD(wp);
      if (collapsed_) {
        const int width = MulDiv(expanded_.right - expanded_.left, static_cast<int>(new_dpi), static_cast<int>(current_dpi_));
        const int height = MulDiv(expanded_.bottom - expanded_.top, static_cast<int>(new_dpi), static_cast<int>(current_dpi_));
        int x = rect->left, y = rect->top;
        if (edge_ == Edge::left || edge_ == Edge::right) y -= (height - (rect->bottom - rect->top)) / 2;
        else x -= (width - (rect->right - rect->left)) / 2;
        collapsed_ = false; transition_ = true;
        SetWindowPos(hwnd_, nullptr, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
        transition_ = false;
      } else SetWindowPos(hwnd_, nullptr, rect->left, rect->top, rect->right - rect->left,
          rect->bottom - rect->top, SWP_NOZORDER | SWP_NOACTIVATE);
      current_dpi_ = new_dpi ? new_dpi : 96;
      Snap(); return 0;
    }
    case WM_GETMINMAXINFO: {
      if (!transition_) {
        auto* limits = reinterpret_cast<MINMAXINFO*>(lp);
        limits->ptMinTrackSize = {Dp(300), Dp(240)};
      }
      return 0;
    }
    case WM_NCHITTEST: {
      POINT point{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)}; ScreenToClient(hwnd_, &point);
      RECT rect{}; GetClientRect(hwnd_, &rect);
      const int radius = std::min(Dp(collapsed_ ? 10 : 16), static_cast<int>(std::min(rect.right, rect.bottom) / 2));
      const int dx = point.x - std::clamp(static_cast<int>(point.x), radius, static_cast<int>(rect.right) - radius);
      const int dy = point.y - std::clamp(static_cast<int>(point.y), radius, static_cast<int>(rect.bottom) - radius);
      if (dx * dx + dy * dy > radius * radius) return HTTRANSPARENT;
      if (collapsed_) return HTCLIENT;
      if (PtInRect(&layout_.resize, point)) return HTBOTTOMRIGHT;
      if (PtInRect(&layout_.menu, point)) return HTCLIENT;
      if (PtInRect(&layout_.drag, point)) return HTCAPTION;
      return HTCLIENT;
    }
    case WM_MOUSEWHEEL: {
      if (GET_WHEEL_DELTA_WPARAM(wp) < 0) ++offset_; else if (offset_ > 0) --offset_;
      InvalidateRect(hwnd_, nullptr, TRUE); return 0;
    }
    case WM_MOUSEMOVE: {
      const POINT point{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
      const bool hovered = PtInRect(&layout_.menu, point) != FALSE;
      if (hovered != menu_hover_) { menu_hover_ = hovered; InvalidateRect(hwnd_, nullptr, FALSE); }
      TRACKMOUSEEVENT tracking{sizeof(TRACKMOUSEEVENT), TME_LEAVE, hwnd_, 0}; TrackMouseEvent(&tracking);
      return 0;
    }
    case WM_MOUSELEAVE: menu_hover_ = false; InvalidateRect(hwnd_, nullptr, FALSE); return 0;
    case WM_RBUTTONUP: if (!collapsed_) ShowMenu(); return 0;
    case WM_LBUTTONUP: {
      if (collapsed_) { Reveal(); return 0; }
      const POINT point{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
      if (PtInRect(&layout_.menu, point)) { ShowMenu(); return 0; }
      if (!editing_) for (const auto& hit : hits_) if (PtInRect(&hit.first, point)) {
        if (hit.second.conflict) open_main_(); else toggle_(hit.second.id, !hit.second.completed);
        break;
      }
      InvalidateRect(hwnd_, nullptr, FALSE); return 0;
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
  if (!VerifyPalettePixels()) return 11;
  bool closed = false, toggled = false;
  DesktopWidget widget([&](const std::string& id, bool done) { toggled = id == "one" && done; },
      [] {}, [] {}, [&] { closed = true; });
  using flutter::EncodableValue;
  flutter::EncodableMap task{{EncodableValue("id"), EncodableValue("one")},
      {EncodableValue("title"), EncodableValue("桌面测试任务")},
      {EncodableValue("due_date"), EncodableValue("2026-10-09")},
      {EncodableValue("completed"), EncodableValue(false)}};
  flutter::EncodableMap state{{EncodableValue("today"), EncodableValue("2026-10-09")},
      {EncodableValue("theme"), EncodableValue("white")},
      {EncodableValue("tasks"), EncodableValue(flutter::EncodableList{EncodableValue(task)})}};
  // The initial snapshot arrives before the native surface is created. Its
  // light material must survive GlassSurface's dark initialization default.
  widget.Update(state);
  if (!widget.Create(false)) return 1;
  if (!widget.surface_) return 2;
  if (GetWindow(widget.hwnd_, GW_OWNER) || (GetWindowLongPtr(widget.hwnd_, GWL_STYLE) & WS_CHILD)) return 3;
  if (widget.PaintState().theme != WidgetTheme::white) return 13;
  BOOL dark = TRUE;
  if (SUCCEEDED(DwmGetWindowAttribute(widget.hwnd_, static_cast<DWMWINDOWATTRIBUTE>(20),
      &dark, sizeof(dark))) && dark) return 13;
  UpdateWindow(widget.hwnd_);
  if (!widget.painted_ || widget.hits_.empty()) return 4;
  const RECT checkbox = widget.hits_.front().first;
  SendMessage(widget.hwnd_, WM_LBUTTONUP, 0, MAKELPARAM((checkbox.left + checkbox.right) / 2, (checkbox.top + checkbox.bottom) / 2));
  if (!toggled) return 5;
  for (const auto* name : {"black", "white", "green", "blue", "unknown"}) {
    state[EncodableValue("theme")] = EncodableValue(name);
    widget.painted_ = false;
    widget.Update(state); UpdateWindow(widget.hwnd_);
    if (widget.PaintState().theme != ParseWidgetTheme(name) || !widget.painted_) return 12;
    const BOOL expected_dark = ParseWidgetTheme(name) == WidgetTheme::white ? FALSE : TRUE;
    if (SUCCEEDED(DwmGetWindowAttribute(widget.hwnd_, static_cast<DWMWINDOWATTRIBUTE>(20),
        &dark, sizeof(dark))) && dark != expected_dark) return 14;
  }
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
  std::puts("Native widget checks passed: four themes, premultiplied palette pixels, stable layout, glass surface, independent lifetime, checkbox, four-edge collapse, hover reveal");
  return 0;
}
