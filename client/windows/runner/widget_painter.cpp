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
  const BYTE alpha = static_cast<BYTE>(input.native_glass ? 184 : 242);
  FillRound(graphics, RectF(0.5f, 0.5f, width - 1.0f, height - 1.0f),
            10.0f, Color(alpha, 37, 51, 44));
  RoundStroke(graphics, RectF(0.5f, 0.5f, width - 1.0f, height - 1.0f),
              10.0f, Color(52, 218, 241, 224));
  Pen pen(Color(245, 194, 222, 205), 1.8f);
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

void DrawEmpty(Graphics& graphics, const RectF& content) {
  const float cx = content.X + content.Width / 2.0f;
  const float cy = content.Y + content.Height / 2.0f - 21.0f;
  SolidBrush halo(Color(15, 198, 229, 207));
  graphics.FillEllipse(&halo, cx - 32.0f, cy - 32.0f, 64.0f, 64.0f);
  RoundStroke(graphics, RectF(cx - 14.0f, cy - 13.0f, 28.0f, 27.0f),
              5.0f, Color(170, 180, 209, 191), 1.5f);
  Pen pen(Color(170, 180, 209, 191), 1.5f);
  pen.SetStartCap(Gdiplus::LineCapRound);
  pen.SetEndCap(Gdiplus::LineCapRound);
  graphics.DrawLine(&pen, cx - 7.0f, cy - 17.0f, cx - 7.0f, cy - 9.0f);
  graphics.DrawLine(&pen, cx + 7.0f, cy - 17.0f, cx + 7.0f, cy - 9.0f);
  graphics.DrawLine(&pen, cx - 14.0f, cy - 4.0f, cx + 14.0f, cy - 4.0f);
  Check(graphics, cx - 8.0f, cy - 3.0f, 16.0f,
         Color(215, 198, 227, 207), 1.7f);
  Text(graphics, L"暂无待办", RectF(content.X, cy + 35.0f,
         content.Width, 22.0f), 14.0f, Color(230, 221, 233, 225),
         Gdiplus::FontStyleRegular, Gdiplus::StringAlignmentCenter);
  // A small window keeps the empty state concise, without pushing its footer.
  if (content.Height > 100.0f) {
    Text(graphics, L"今天的任务会显示在这里", RectF(content.X, cy + 62.0f,
           content.Width, 20.0f), 11.0f, Color(155, 182, 198, 188),
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
  if (input.collapsed) {
    DrawCollapsed(graphics, input, width, height);
    return bitmap;
  }

  GraphicsPath card;
  RoundedPath(card, RectF(0.5f, 0.5f, width - 1.0f, height - 1.0f), 16.0f);
  const Color top(static_cast<BYTE>(input.native_glass ? 158 : 238), 37, 50, 44);
  const Color bottom(static_cast<BYTE>(input.native_glass ? 174 : 244), 25, 37, 32);
  Gdiplus::LinearGradientBrush tint(RectF(0.0f, 0.0f, width, height), top,
                                     bottom, Gdiplus::LinearGradientModeVertical);
  graphics.FillPath(&tint, &card);
  Pen border(Color(42, 227, 242, 232), 1.0f);
  graphics.DrawPath(&border, &card);
  graphics.SetClip(&card);

  // A small, custom vector mark gives the widget a recognizable visual anchor.
  FillRound(graphics, RectF(22.0f, 22.0f, 30.0f, 30.0f), 10.0f,
              Color(23, 201, 230, 211));
  Check(graphics, 26.0f, 25.0f, 23.0f, Color(235, 198, 225, 207), 2.0f);
  Text(graphics, L"今天", RectF(62.0f, 18.0f, width - 124.0f, 38.0f),
         23.0f, Color(255, 242, 247, 243), Gdiplus::FontStyleBold);

  const RectF menu = LogicalRect(layout.menu, scale);
  if (input.menu_hover) {
    FillRound(graphics, menu, 11.0f, Color(24, 236, 247, 240));
  }
  SolidBrush dots(Color(static_cast<BYTE>(input.menu_hover ? 245 : 180),
                         217, 232, 222));
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
         24.0f), 11.5f, Color(200, 184, 202, 190));
  const std::wstring pending = remaining ? std::to_wstring(remaining) +
      L" 件待完成" : (input.tasks.empty() ? L"" : L"全部完成");
  Text(graphics, pending, RectF(width - 116.0f, 66.0f, 94.0f, 24.0f),
         11.5f, Color(210, 179, 208, 189), Gdiplus::FontStyleRegular,
         Gdiplus::StringAlignmentFar);

  if (input.tasks.empty()) {
    DrawEmpty(graphics, LogicalRect(layout.content, scale));
  } else {
    for (const auto& hit : layout.tasks) {
      const auto& task = input.tasks[hit.task_index];
      const RectF row = LogicalRect(hit.row, scale);
      FillRound(graphics, row, 12.0f,
                  Color(static_cast<BYTE>(task.completed ? 9 : 19),
                         229, 244, 234));
      const RectF check = LogicalRect(hit.checkbox, scale);
      const float cx = check.X + check.Width / 2.0f;
      const float cy = check.Y + check.Height / 2.0f;
      if (task.conflict) {
        Pen warning(Color(225, 226, 190, 136), 1.5f);
        graphics.DrawEllipse(&warning, cx - 9.5f, cy - 9.5f, 19.0f, 19.0f);
        warning.SetStartCap(Gdiplus::LineCapRound);
        warning.SetEndCap(Gdiplus::LineCapRound);
        graphics.DrawLine(&warning, cx, cy - 4.0f, cx, cy + 1.0f);
        SolidBrush dot(Color(225, 226, 190, 136));
        graphics.FillEllipse(&dot, cx - 1.0f, cy + 4.0f, 2.0f, 2.0f);
      } else if (task.completed) {
        SolidBrush filled(Color(static_cast<BYTE>(input.editing ? 130 : 220),
                                  158, 198, 172));
        graphics.FillEllipse(&filled, cx - 10.0f, cy - 10.0f, 20.0f, 20.0f);
        Check(graphics, cx - 9.0f, cy - 9.0f, 18.0f,
               Color(245, 31, 61, 43), 1.8f);
      } else {
        Pen outline(Color(static_cast<BYTE>(input.editing ? 105 : 180),
                            177, 205, 188), 1.4f);
        graphics.DrawEllipse(&outline, cx - 9.5f, cy - 9.5f, 19.0f, 19.0f);
      }
      const float right_space = task.priority > 0 && !task.completed ? 31.0f : 16.0f;
      Text(graphics, task.title,
           RectF(row.X + 49.0f, row.Y, row.Width - 49.0f - right_space,
                 row.Height),
           13.5f, task.completed ? Color(160, 176, 192, 182)
                                 : Color(static_cast<BYTE>(input.editing ? 190 : 250),
                                          234, 241, 236),
           task.completed ? Gdiplus::FontStyleStrikeout
                          : Gdiplus::FontStyleRegular);
      if (task.priority > 0 && !task.completed) {
        SolidBrush priority(task.priority > 1 ? Color(200, 222, 182, 139)
                                             : Color(160, 170, 205, 185));
        graphics.FillEllipse(&priority, row.GetRight() - 20.0f,
                               row.Y + row.Height / 2.0f - 2.2f, 4.4f, 4.4f);
      }
    }
  }

  const float footer_top = height - 57.0f;
  Pen separator(Color(20, 235, 244, 239), 1.0f);
  graphics.DrawLine(&separator, 22.0f, footer_top, width - 22.0f, footer_top);
  const std::wstring progress = L"已完成 " + std::to_wstring(completed) +
                                L" / " + std::to_wstring(input.tasks.size());
  Text(graphics, progress, RectF(22.0f, footer_top + 7.0f,
         width - 73.0f, 23.0f), 10.5f, Color(170, 182, 201, 189));
  if (input.has_error) {
    SolidBrush issue(Color(235, 224, 180, 123));
    graphics.FillEllipse(&issue, width - 28.0f, footer_top + 16.0f, 4.0f, 4.0f);
  }
  const RectF track(22.0f, height - 18.0f, width - 44.0f, 3.0f);
  FillRound(graphics, track, 1.5f, Color(23, 219, 238, 226));
  if (!input.tasks.empty() && completed) {
    const float fraction = static_cast<float>(completed) /
                           static_cast<float>(input.tasks.size());
    FillRound(graphics, RectF(track.X, track.Y, track.Width * fraction,
              track.Height), 1.5f, Color(215, 160, 205, 176));
  }
  // The corner affordance is deliberately quiet; the whole corner is a hit area.
  Pen grip(Color(58, 212, 230, 219), 1.0f);
  grip.SetStartCap(Gdiplus::LineCapRound);
  grip.SetEndCap(Gdiplus::LineCapRound);
  graphics.DrawLine(&grip, width - 10.0f, height - 5.0f,
                     width - 5.0f, height - 10.0f);
  graphics.DrawLine(&grip, width - 15.0f, height - 5.0f,
                     width - 5.0f, height - 15.0f);
  return bitmap;
}
}  // namespace

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
