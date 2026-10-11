#include "widget_painter.h"

#include <gdiplus.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <cwchar>
#include <memory>

namespace {
using Gdiplus::Color;
using Gdiplus::Graphics;
using Gdiplus::GraphicsPath;
using Gdiplus::Pen;
using Gdiplus::RectF;
using Gdiplus::SolidBrush;

struct Palette {
  Color top, bottom, text, secondary, muted;
  Color accent, soft_accent, check_ink, row, border, warning;
  bool light;
};

Palette Colors(WidgetTheme theme) {
  switch (theme) {
    case WidgetTheme::black:
      return {Color(255, 39, 41, 44), Color(255, 24, 26, 29),
          Color(255, 244, 245, 247), Color(255, 194, 198, 205),
          Color(255, 180, 184, 192), Color(255, 183, 191, 204),
          Color(255, 211, 217, 228), Color(255, 36, 40, 47),
          Color(255, 238, 241, 247), Color(255, 231, 235, 244),
          Color(255, 224, 184, 127), false};
    case WidgetTheme::white:
      return {Color(255, 250, 251, 250), Color(255, 230, 235, 232),
          Color(255, 28, 35, 31), Color(255, 72, 87, 78),
          Color(255, 96, 109, 102), Color(255, 73, 89, 80),
          Color(255, 68, 88, 77), Color(255, 250, 252, 250),
          Color(255, 53, 69, 59), Color(255, 74, 94, 83),
          Color(255, 151, 94, 35), true};
    case WidgetTheme::blue:
      return {Color(255, 36, 49, 67), Color(255, 24, 35, 53),
          Color(255, 240, 246, 253), Color(255, 184, 203, 225),
          Color(255, 177, 191, 210), Color(255, 156, 188, 227),
          Color(255, 191, 216, 245), Color(255, 28, 48, 75),
          Color(255, 224, 237, 252), Color(255, 221, 236, 253),
          Color(255, 229, 188, 130), false};
    case WidgetTheme::green:
    default:
      return {Color(255, 37, 50, 44), Color(255, 25, 37, 32),
          Color(255, 242, 247, 243), Color(255, 184, 202, 190),
          Color(255, 176, 192, 182), Color(255, 160, 205, 176),
          Color(255, 198, 225, 207), Color(255, 31, 61, 43),
          Color(255, 229, 244, 234), Color(255, 227, 242, 232),
          Color(255, 224, 180, 123), false};
  }
}

Color Opacity(const Color& color, int alpha) {
  return Color(static_cast<BYTE>(alpha), color.GetR(), color.GetG(), color.GetB());
}

class GraphicsSession {
 public:
  GraphicsSession() {
    Gdiplus::GdiplusStartupInput options;
    ready_ = Gdiplus::GdiplusStartup(&token_, &options, nullptr) == Gdiplus::Ok;
  }
  ~GraphicsSession() {
    if (ready_) Gdiplus::GdiplusShutdown(token_);
  }
  bool ready() const { return ready_; }

 private:
  ULONG_PTR token_ = 0;
  bool ready_ = false;
};

bool GraphicsReady() {
  static GraphicsSession session;
  return session.ready();
}

float Scale(const WidgetPaintInput& input) {
  return static_cast<float>(input.dpi ? input.dpi : 96) / 96.0f;
}

RECT PhysicalRect(float x, float y, float width, float height, float scale) {
  return {static_cast<LONG>(std::lround(x * scale)),
          static_cast<LONG>(std::lround(y * scale)),
          static_cast<LONG>(std::lround((x + width) * scale)),
          static_cast<LONG>(std::lround((y + height) * scale))};
}

RectF LogicalRect(const RECT& rect, float scale) {
  return RectF(static_cast<float>(rect.left) / scale,
               static_cast<float>(rect.top) / scale,
               static_cast<float>(rect.right - rect.left) / scale,
               static_cast<float>(rect.bottom - rect.top) / scale);
}

void RoundedPath(GraphicsPath& path, const RectF& rect, float radius) {
  const float diameter = std::min(radius * 2.0f,
                                  std::min(rect.Width, rect.Height));
  if (diameter <= 0.0f) return;
  path.AddArc(rect.X, rect.Y, diameter, diameter, 180.0f, 90.0f);
  path.AddArc(rect.GetRight() - diameter, rect.Y, diameter, diameter,
              270.0f, 90.0f);
  path.AddArc(rect.GetRight() - diameter, rect.GetBottom() - diameter,
              diameter, diameter, 0.0f, 90.0f);
  path.AddArc(rect.X, rect.GetBottom() - diameter, diameter, diameter,
              90.0f, 90.0f);
  path.CloseFigure();
}

void FillRound(Graphics& graphics, const RectF& rect, float radius, Color color) {
  GraphicsPath path;
  RoundedPath(path, rect, radius);
  SolidBrush brush(color);
  graphics.FillPath(&brush, &path);
}

void RoundStroke(Graphics& graphics, const RectF& rect, float radius,
                 Color color, float width = 1.0f) {
  GraphicsPath path;
  RoundedPath(path, rect, radius);
  Pen pen(color, width);
  graphics.DrawPath(&pen, &path);
}

void Text(Graphics& graphics, const std::wstring& value, const RectF& bounds,
          float size, Color color, int style = Gdiplus::FontStyleRegular,
          Gdiplus::StringAlignment alignment = Gdiplus::StringAlignmentNear) {
  Gdiplus::Font font(L"Microsoft YaHei UI", size, style, Gdiplus::UnitPixel);
  Gdiplus::StringFormat format;
  format.SetAlignment(alignment);
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
  SolidBrush brush(color);
  graphics.DrawString(value.c_str(), static_cast<INT>(value.size()),
                      &font, bounds, &format, &brush);
}

void Check(Graphics& graphics, float x, float y, float size, Color color,
           float stroke) {
  Pen pen(color, stroke);
  pen.SetStartCap(Gdiplus::LineCapRound);
  pen.SetEndCap(Gdiplus::LineCapRound);
  pen.SetLineJoin(Gdiplus::LineJoinRound);
  const Gdiplus::PointF points[] = {
      {x + size * 0.22f, y + size * 0.52f},
      {x + size * 0.43f, y + size * 0.73f},
      {x + size * 0.79f, y + size * 0.31f}};
  graphics.DrawLines(&pen, points, 3);
}

std::wstring DateLabel(const std::wstring& today) {
  if (today.size() != 10 || today[4] != L'-' || today[7] != L'-') {
    return L"";
  }
  const auto digit = [&](size_t i) -> int {
    return today[i] >= L'0' && today[i] <= L'9' ? today[i] - L'0' : -1;
  };
  for (size_t i : {size_t{0}, size_t{1}, size_t{2}, size_t{3},
                   size_t{5}, size_t{6}, size_t{8}, size_t{9}}) {
    if (digit(i) < 0) return today;
  }
  SYSTEMTIME date{};
  date.wYear = static_cast<WORD>(digit(0) * 1000 + digit(1) * 100 +
                                 digit(2) * 10 + digit(3));
  date.wMonth = static_cast<WORD>(digit(5) * 10 + digit(6));
  date.wDay = static_cast<WORD>(digit(8) * 10 + digit(9));
  FILETIME file{};
  SYSTEMTIME complete{};
  if (!SystemTimeToFileTime(&date, &file) ||
      !FileTimeToSystemTime(&file, &complete)) return today;
  const wchar_t* days[] = {L"周日", L"周一", L"周二", L"周三",
                            L"周四", L"周五", L"周六"};
  return std::to_wstring(date.wMonth) + L"月" +
         std::to_wstring(date.wDay) + L"日  ·  " + days[complete.wDayOfWeek];
}

void DrawCollapsed(Graphics& graphics, const WidgetPaintInput& input,
                   float width, float height) {
  const Palette palette = Colors(input.theme);
  const BYTE alpha = static_cast<BYTE>(input.native_glass ? 184 : 242);
  FillRound(graphics, RectF(0.5f, 0.5f, width - 1.0f, height - 1.0f),
            10.0f, Opacity(palette.top, alpha));
  RoundStroke(graphics, RectF(0.5f, 0.5f, width - 1.0f, height - 1.0f),
              10.0f, Opacity(palette.border, palette.light ? 40 : 52));
  Pen pen(Opacity(palette.soft_accent, 245), 1.8f);
  pen.SetStartCap(Gdiplus::LineCapRound);
  pen.SetEndCap(Gdiplus::LineCapRound);
  const float x = width / 2.0f, y = height / 2.0f;
  if (input.edge == WidgetEdge::left || input.edge == WidgetEdge::right) {
    const float sign = input.edge == WidgetEdge::left ? 1.0f : -1.0f;
    graphics.DrawLine(&pen, x - sign * 2.0f, y - 4.0f,
                       x + sign * 2.0f, y);
    graphics.DrawLine(&pen, x + sign * 2.0f, y,
                       x - sign * 2.0f, y + 4.0f);
  } else {
    const float sign = input.edge == WidgetEdge::top ? 1.0f : -1.0f;
    graphics.DrawLine(&pen, x - 4.0f, y - sign * 2.0f,
                       x, y + sign * 2.0f);
    graphics.DrawLine(&pen, x, y + sign * 2.0f,
                       x + 4.0f, y - sign * 2.0f);
  }
}

void DrawEmpty(Graphics& graphics, const RectF& content, const Palette& palette) {
  const float cx = content.X + content.Width / 2.0f;
  const float cy = content.Y + content.Height / 2.0f - 21.0f;
  SolidBrush halo(Opacity(palette.soft_accent, palette.light ? 10 : 15));
  graphics.FillEllipse(&halo, cx - 32.0f, cy - 32.0f, 64.0f, 64.0f);
  RoundStroke(graphics, RectF(cx - 14.0f, cy - 13.0f, 28.0f, 27.0f),
              5.0f, Opacity(palette.secondary, palette.light ? 220 : 170), 1.5f);
  Pen pen(Opacity(palette.secondary, palette.light ? 220 : 170), 1.5f);
  pen.SetStartCap(Gdiplus::LineCapRound);
  pen.SetEndCap(Gdiplus::LineCapRound);
  graphics.DrawLine(&pen, cx - 7.0f, cy - 17.0f, cx - 7.0f, cy - 9.0f);
  graphics.DrawLine(&pen, cx + 7.0f, cy - 17.0f, cx + 7.0f, cy - 9.0f);
  graphics.DrawLine(&pen, cx - 14.0f, cy - 4.0f, cx + 14.0f, cy - 4.0f);
  Check(graphics, cx - 8.0f, cy - 3.0f, 16.0f,
         Opacity(palette.soft_accent, 235), 1.7f);
  Text(graphics, L"暂无待办", RectF(content.X, cy + 35.0f,
         content.Width, 22.0f), 14.0f, Opacity(palette.text, 230),
         Gdiplus::FontStyleRegular, Gdiplus::StringAlignmentCenter);
  // A small window keeps the empty state concise, without pushing its footer.
  if (content.Height > 100.0f) {
    Text(graphics, L"今天的任务会显示在这里", RectF(content.X, cy + 62.0f,
           content.Width, 20.0f), 11.0f,
           Opacity(palette.secondary, palette.light ? 220 : 155),
           Gdiplus::FontStyleRegular, Gdiplus::StringAlignmentCenter);
  }
}

std::unique_ptr<Gdiplus::Bitmap> Render(const WidgetPaintInput& input,
                                      const WidgetPaintLayout& layout) {
  if (!GraphicsReady() || input.width <= 0 || input.height <= 0) return nullptr;
  auto bitmap = std::make_unique<Gdiplus::Bitmap>(input.width, input.height,
                                                 PixelFormat32bppPARGB);
  if (bitmap->GetLastStatus() != Gdiplus::Ok) return nullptr;
  Graphics graphics(bitmap.get());
  graphics.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
  graphics.Clear(Color(0, 0, 0, 0));
  graphics.SetCompositingMode(Gdiplus::CompositingModeSourceOver);
  graphics.SetCompositingQuality(Gdiplus::CompositingQualityHighQuality);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
  const float scale = Scale(input);
  graphics.ScaleTransform(scale, scale);
  const float width = static_cast<float>(input.width) / scale;
  const float height = static_cast<float>(input.height) / scale;
  const Palette palette = Colors(input.theme);
  if (input.collapsed) {
    DrawCollapsed(graphics, input, width, height);
    return bitmap;
  }

  GraphicsPath card;
  RoundedPath(card, RectF(0.5f, 0.5f, width - 1.0f, height - 1.0f), 16.0f);
  const Color top = Opacity(palette.top, input.native_glass ? 158 : 238);
  const Color bottom = Opacity(palette.bottom, input.native_glass ? 174 : 244);
  Gdiplus::LinearGradientBrush tint(RectF(0.0f, 0.0f, width, height), top,
                                     bottom, Gdiplus::LinearGradientModeVertical);
  graphics.FillPath(&tint, &card);
  Pen border(Opacity(palette.border, palette.light ? 36 : 42), 1.0f);
  graphics.DrawPath(&border, &card);
  graphics.SetClip(&card);

  // A small, custom vector mark gives the widget a recognizable visual anchor.
  FillRound(graphics, RectF(22.0f, 22.0f, 30.0f, 30.0f), 10.0f,
              Opacity(palette.soft_accent, palette.light ? 12 : 23));
  Check(graphics, 26.0f, 25.0f, 23.0f,
         Opacity(palette.soft_accent, 235), 2.0f);
  Text(graphics, L"今天", RectF(62.0f, 18.0f, width - 124.0f, 38.0f),
         23.0f, palette.text, Gdiplus::FontStyleBold);

  const RectF menu = LogicalRect(layout.menu, scale);
  if (input.menu_hover) {
    FillRound(graphics, menu, 11.0f,
                Opacity(palette.border, palette.light ? 12 : 24));
  }
  SolidBrush dots(Opacity(palette.secondary,
                          input.menu_hover || palette.light ? 245 : 180));
  for (int i = -1; i <= 1; ++i) {
    graphics.FillEllipse(&dots, menu.X + menu.Width / 2.0f +
                           static_cast<float>(i) * 5.0f - 1.3f,
                           menu.Y + menu.Height / 2.0f - 1.3f, 2.6f, 2.6f);
  }

  const size_t completed = static_cast<size_t>(std::count_if(
      input.tasks.begin(), input.tasks.end(),
      [](const WidgetPaintTask& task) { return task.completed; }));
  const size_t remaining = input.tasks.size() - completed;
  Text(graphics, DateLabel(input.today), RectF(22.0f, 66.0f, width - 138.0f,
         24.0f), 11.5f, Opacity(palette.secondary, palette.light ? 235 : 200));
  const std::wstring pending = remaining ? std::to_wstring(remaining) +
      L" 件待完成" : (input.tasks.empty() ? L"" : L"全部完成");
  Text(graphics, pending, RectF(width - 116.0f, 66.0f, 94.0f, 24.0f),
         11.5f, Opacity(palette.soft_accent, palette.light ? 235 : 210),
         Gdiplus::FontStyleRegular,
         Gdiplus::StringAlignmentFar);

  if (input.tasks.empty()) {
    DrawEmpty(graphics, LogicalRect(layout.content, scale), palette);
  } else {
    for (const auto& hit : layout.tasks) {
      const auto& task = input.tasks[hit.task_index];
      const RectF row = LogicalRect(hit.row, scale);
      FillRound(graphics, row, 12.0f,
                  Opacity(palette.row, palette.light
                      ? (task.completed ? 5 : 9) : (task.completed ? 9 : 19)));
      const RectF check = LogicalRect(hit.checkbox, scale);
      const float cx = check.X + check.Width / 2.0f;
      const float cy = check.Y + check.Height / 2.0f;
      if (task.conflict) {
        Pen warning(Opacity(palette.warning, 235), 1.5f);
        graphics.DrawEllipse(&warning, cx - 9.5f, cy - 9.5f, 19.0f, 19.0f);
        warning.SetStartCap(Gdiplus::LineCapRound);
        warning.SetEndCap(Gdiplus::LineCapRound);
        graphics.DrawLine(&warning, cx, cy - 4.0f, cx, cy + 1.0f);
        SolidBrush dot(Opacity(palette.warning, 235));
        graphics.FillEllipse(&dot, cx - 1.0f, cy + 4.0f, 2.0f, 2.0f);
      } else if (task.completed) {
        SolidBrush filled(Opacity(palette.accent, input.editing ? 150 : 230));
        graphics.FillEllipse(&filled, cx - 10.0f, cy - 10.0f, 20.0f, 20.0f);
        Check(graphics, cx - 9.0f, cy - 9.0f, 18.0f,
               Opacity(palette.check_ink, 245), 1.8f);
      } else {
        Pen outline(Opacity(palette.secondary,
                             input.editing ? 125 : (palette.light ? 230 : 180)),
                      1.4f);
        graphics.DrawEllipse(&outline, cx - 9.5f, cy - 9.5f, 19.0f, 19.0f);
      }
      const float right_space = task.priority > 0 && !task.completed ? 31.0f : 16.0f;
      Text(graphics, task.title,
           RectF(row.X + 49.0f, row.Y, row.Width - 49.0f - right_space,
                 row.Height),
           13.5f, task.completed ? Opacity(palette.muted, palette.light ? 220 : 160)
                                 : Opacity(palette.text, input.editing ? 190 : 250),
           task.completed ? Gdiplus::FontStyleStrikeout
                          : Gdiplus::FontStyleRegular);
      if (task.priority > 0 && !task.completed) {
        SolidBrush priority(task.priority > 1 ? Opacity(palette.warning, 220)
                                             : Opacity(palette.accent, 200));
        graphics.FillEllipse(&priority, row.GetRight() - 20.0f,
                               row.Y + row.Height / 2.0f - 2.2f, 4.4f, 4.4f);
      }
    }
  }

  const float footer_top = height - 57.0f;
  Pen separator(Opacity(palette.border, palette.light ? 30 : 20), 1.0f);
  graphics.DrawLine(&separator, 22.0f, footer_top, width - 22.0f, footer_top);
  const std::wstring progress = L"已完成 " + std::to_wstring(completed) +
                                L" / " + std::to_wstring(input.tasks.size());
  Text(graphics, progress, RectF(22.0f, footer_top + 7.0f,
         width - 73.0f, 23.0f), 10.5f,
         Opacity(palette.secondary, palette.light ? 235 : 170));
  if (input.has_error) {
    SolidBrush issue(Opacity(palette.warning, 235));
    graphics.FillEllipse(&issue, width - 28.0f, footer_top + 16.0f, 4.0f, 4.0f);
  }
  const RectF track(22.0f, height - 18.0f, width - 44.0f, 3.0f);
  FillRound(graphics, track, 1.5f,
              Opacity(palette.border, palette.light ? 30 : 23));
  if (!input.tasks.empty() && completed) {
    const float fraction = static_cast<float>(completed) /
                           static_cast<float>(input.tasks.size());
    FillRound(graphics, RectF(track.X, track.Y, track.Width * fraction,
              track.Height), 1.5f, Opacity(palette.accent, 235));
  }
  // The corner affordance is deliberately quiet; the whole corner is a hit area.
  Pen grip(Opacity(palette.border, palette.light ? 80 : 58), 1.0f);
  grip.SetStartCap(Gdiplus::LineCapRound);
  grip.SetEndCap(Gdiplus::LineCapRound);
  graphics.DrawLine(&grip, width - 10.0f, height - 5.0f,
                     width - 5.0f, height - 10.0f);
  graphics.DrawLine(&grip, width - 15.0f, height - 5.0f,
                     width - 5.0f, height - 15.0f);
  return bitmap;
}
}  // namespace

WidgetTheme ParseWidgetTheme(const std::string& name) {
  if (name == "black") return WidgetTheme::black;
  if (name == "white") return WidgetTheme::white;
  if (name == "blue") return WidgetTheme::blue;
  return WidgetTheme::green;
}

WidgetPaintLayout LayoutWidget(const WidgetPaintInput& input) {
  WidgetPaintLayout layout;
  const float scale = Scale(input);
  const float width = static_cast<float>(input.width) / scale;
  const float height = static_cast<float>(input.height) / scale;
  if (input.collapsed) {
    layout.drag = {0, 0, input.width, input.height};
    return layout;
  }
  layout.drag = PhysicalRect(16.0f, 12.0f, std::max(0.0f, width - 82.0f),
                             82.0f, scale);
  layout.menu = PhysicalRect(width - 58.0f, 19.0f, 36.0f, 36.0f, scale);
  layout.resize = PhysicalRect(width - 18.0f, height - 18.0f,
                               18.0f, 18.0f, scale);
  const float available = std::max(0.0f, height - 172.0f);
  layout.row_capacity = static_cast<size_t>(std::max(1.0f,
                                                 std::floor(available / 54.0f)));
  layout.content = PhysicalRect(22.0f, 104.0f, std::max(0.0f, width - 44.0f),
                                std::max(0.0f, height - 171.0f), scale);
  const size_t maximum_offset = input.tasks.size() > layout.row_capacity
      ? input.tasks.size() - layout.row_capacity : 0;
  layout.offset = std::min(input.offset, maximum_offset);
  for (size_t i = layout.offset; i < input.tasks.size() &&
       i - layout.offset < layout.row_capacity; ++i) {
    const float y = 104.0f + static_cast<float>(i - layout.offset) * 54.0f;
    WidgetTaskHit hit;
    hit.row = PhysicalRect(22.0f, y, std::max(0.0f, width - 44.0f), 46.0f, scale);
    hit.checkbox = PhysicalRect(27.0f, y + 5.0f, 36.0f, 36.0f, scale);
    hit.task_index = i;
    layout.tasks.push_back(hit);
  }
  return layout;
}

WidgetPaintLayout PaintWidget(HDC target, const WidgetPaintInput& input) {
  WidgetPaintLayout layout = LayoutWidget(input);
  auto bitmap = Render(input, layout);
  if (!bitmap || !target) return layout;
  DIBSECTION dib{};
  if (GetObject(GetCurrentObject(target, OBJ_BITMAP),
                  static_cast<int>(sizeof(dib)), &dib) == 0 ||
      !dib.dsBm.bmBits || dib.dsBm.bmBitsPixel != 32 ||
      dib.dsBm.bmWidth < input.width || dib.dsBm.bmHeight < input.height) {
    return layout;
  }
  Gdiplus::BitmapData pixels{};
  const Gdiplus::Rect rect(0, 0, input.width, input.height);
  if (bitmap->LockBits(&rect, Gdiplus::ImageLockModeRead, PixelFormat32bppPARGB,
                        &pixels) != Gdiplus::Ok) return layout;
  auto* destination = static_cast<BYTE*>(dib.dsBm.bmBits);
  const auto* source = static_cast<const BYTE*>(pixels.Scan0);
  for (int y = 0; y < input.height; ++y) {
    // The caller supplies a top-down DIB. GetObject can normalize its height
    // sign, so that metadata must not reverse the caller's row orientation.
    std::memcpy(destination + static_cast<std::ptrdiff_t>(y) *
                              dib.dsBm.bmWidthBytes,
                source + static_cast<std::ptrdiff_t>(y) * pixels.Stride,
                static_cast<size_t>(input.width) * 4);
  }
  bitmap->UnlockBits(&pixels);
  layout.painted = true;
  return layout;
}

bool SaveWidgetPreview(const WidgetPaintInput& input,
                       const std::wstring& png_path) {
  auto bitmap = Render(input, LayoutWidget(input));
  if (!bitmap) return false;
  UINT count = 0, size = 0;
  if (Gdiplus::GetImageEncodersSize(&count, &size) != Gdiplus::Ok || !size) {
    return false;
  }
  std::vector<BYTE> buffer(size);
  auto* encoders = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  if (Gdiplus::GetImageEncoders(count, size, encoders) != Gdiplus::Ok) return false;
  for (UINT i = 0; i < count; ++i) {
    if (std::wcscmp(encoders[i].MimeType, L"image/png") == 0) {
      return bitmap->Save(png_path.c_str(), &encoders[i].Clsid, nullptr) ==
             Gdiplus::Ok;
    }
  }
  return false;
}
