#ifndef PRIVATE_TODO_WIDGET_PAINTER_H_
#define PRIVATE_TODO_WIDGET_PAINTER_H_

#include <windows.h>
#include <cstddef>
#include <string>
#include <vector>

// Coordinates and dimensions are physical pixels. Text and spacing scale with
// dpi. Task indices refer to the input vector, including when it is scrolled.
enum class WidgetEdge { none, left, right, top, bottom };
enum class WidgetTheme { black, white, green, blue };

// Themes are sent by the app. Unknown names retain the original green design.
WidgetTheme ParseWidgetTheme(const std::string& name);

struct WidgetPaintTask {
  std::wstring title;
  bool completed = false;
  bool conflict = false;
  int priority = 0;
};

struct WidgetPaintInput {
  int width = 340;
  int height = 420;
  UINT dpi = 96;
  bool collapsed = false;
  WidgetEdge edge = WidgetEdge::none;
  WidgetTheme theme = WidgetTheme::green;
  bool native_glass = true;
  bool editing = false;
  bool menu_hover = false;
  bool has_error = false;
  std::wstring today;  // YYYY-MM-DD; converted into a short Chinese date.
  std::vector<WidgetPaintTask> tasks;
  size_t offset = 0;
};

struct WidgetTaskHit {
  RECT row{};
  RECT checkbox{};
  size_t task_index = 0;
};

struct WidgetPaintLayout {
  RECT drag{};
  RECT menu{};
  RECT resize{};
  RECT content{};
  std::vector<WidgetTaskHit> tasks;
  size_t offset = 0;
  size_t row_capacity = 0;
  bool painted = false;
};

WidgetPaintLayout LayoutWidget(const WidgetPaintInput& input);

// Select a top-down 32-bit DIBSection (biHeight = -height) into target before
// calling. The painter copies premultiplied BGRA pixels into its bits in visual
// top-to-bottom order, ready for a premultiplied compositor.
// It initializes GDI+ internally and does not draw through GDI's HDC alpha path.
WidgetPaintLayout PaintWidget(HDC target, const WidgetPaintInput& input);

// Saves the identical painter output for native CI / visual verification.
bool SaveWidgetPreview(const WidgetPaintInput& input,
                       const std::wstring& png_path);

#endif  // PRIVATE_TODO_WIDGET_PAINTER_H_
