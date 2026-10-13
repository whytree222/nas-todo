import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../daily_celebration.dart';

final dailyCelebrationRouteObserver = RouteObserver<ModalRoute<dynamic>>();

Future<void> showDailyCelebration(BuildContext context, DailyCelebration celebration) =>
    showDialog<void>(
      context: context,
      builder: (_) => DailyCelebrationDialog(celebration: celebration),
    );

/// A finite, quiet celebration: no repeating animation, sound or forced delay.
class DailyCelebrationDialog extends StatefulWidget {
  const DailyCelebrationDialog({super.key, required this.celebration});
  final DailyCelebration celebration;

  @override
  State<DailyCelebrationDialog> createState() => _DailyCelebrationDialogState();
}

class _DailyCelebrationDialogState extends State<DailyCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _animation.forward();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark ? const Color(0xff242a3e) : const Color(0xfffffbef);
    final foreground = dark ? const Color(0xfff6f1df) : const Color(0xff303840);
    return Dialog(
      key: const ValueKey('daily-celebration-dialog'),
      backgroundColor: background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(
        key: const ValueKey('daily-celebration-artifact'),
        child: ColoredBox(
          color: background,
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xfff1c75b).withValues(alpha: dark ? .17 : .24),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('今日达成', style: TextStyle(
                        color: foreground, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '收起鼓励',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: foreground.withValues(alpha: .65), size: 20),
                    ),
                  ],
                ),
                Semantics(
                  label: '一颗笑着的金色星星，身边飘着彩色纸屑',
                  image: true,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      height: 195,
                      width: double.infinity,
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (_, _) => CustomPaint(
                          painter: _HappyStarPainter(progress: _animation.value, dark: dark),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Semantics(
                  liveRegion: true,
                  child: Text(widget.celebration.message,
                    key: const ValueKey('daily-celebration-message'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: foreground, fontSize: 25, height: 1.35, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 13),
                Text('今天的 ${widget.celebration.taskCount} 件待办，全部完成！',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: foreground, fontWeight: FontWeight.w600, height: 1.5, fontSize: 14)),
                const SizedBox(height: 7),
                Text('认真走过的每一步，都算数。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: foreground.withValues(alpha: .72), height: 1.6, fontSize: 13)),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('daily-celebration-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff325b52),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                    ),
                    icon: const Icon(Icons.favorite_rounded, size: 17),
                    label: const Text('收下这份鼓励'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}

class _HappyStarPainter extends CustomPainter {
  const _HappyStarPainter({required this.progress, required this.dark});
  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 103);
    final settle = Curves.easeOutBack.transform((progress * 2).clamp(0.0, 1.0));
    final scale = .72 + .28 * settle;
    final float = math.sin(progress * math.pi * 3) * (1 - progress) * 5;
    final glow = Paint()..color = const Color(0xffffd96c).withValues(alpha: dark ? .10 : .20);
    canvas.drawOval(Rect.fromCenter(center: center.translate(0, 5), width: 185, height: 158), glow);

    const colors = [Color(0xff4caa96), Color(0xffec8f98), Color(0xff6f9bd3), Color(0xffe1ba51)];
    for (var index = 0; index < 16; index++) {
      final angle = index * math.pi / 8 + .13;
      final radius = 95.0 + (index % 3) * 9 + math.sin(progress * math.pi) * 13;
      final point = center + Offset(math.cos(angle) * radius, math.sin(angle) * radius * .73);
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(angle + progress * math.pi / 2);
      final paint = Paint()..color = colors[index % colors.length].withValues(alpha: .9);
      if (index % 3 == 0) {
        canvas.drawCircle(Offset.zero, 3.2, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-2, -5, 4, 10), const Radius.circular(2)), paint);
      }
      canvas.restore();
    }
    canvas.save();
    canvas.translate(center.dx, center.dy + float);
    canvas.scale(scale);
    canvas.rotate(math.sin(progress * math.pi * 2) * (1 - progress) * .09);
    final star = _roundedStar();
    canvas.drawShadow(star, const Color(0xffc58e23).withValues(alpha: .25), 9, true);
    canvas.drawPath(star, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xffffe6a0), Color(0xffffc84e)],
    ).createShader(const Rect.fromLTWH(-78, -78, 156, 156)));
    canvas.drawCircle(const Offset(-29, 19), 9, Paint()..color = const Color(0xfff4a189).withValues(alpha: .65));
    canvas.drawCircle(const Offset(29, 19), 9, Paint()..color = const Color(0xfff4a189).withValues(alpha: .65));
    final ink = Paint()..color = const Color(0xff5b4835)..style = PaintingStyle.stroke
      ..strokeWidth = 4.2..strokeCap = StrokeCap.round;
    for (final x in [-19.0, 19.0]) {
      canvas.drawArc(Rect.fromCenter(center: Offset(x, 7), width: 11, height: 13), math.pi, math.pi, false, ink);
    }
    canvas.drawArc(const Rect.fromLTWH(-13, 10, 26, 23), 0, math.pi, false, ink);
    canvas.drawOval(const Rect.fromLTWH(-30, -32, 20, 9), Paint()..color = Colors.white.withValues(alpha: .6));
    canvas.restore();
    _sparkle(canvas, Offset(size.width * .22, 33), 8, colors[2]);
    _sparkle(canvas, Offset(size.width * .80, 61), 7, colors[0]);
  }

  Path _roundedStar() {
    final points = List.generate(10, (index) {
      final radius = index.isEven ? 78.0 : 42.0;
      final angle = -math.pi / 2 + index * math.pi / 5;
      return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    });
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final previous = points[(index + 9) % 10];
      final point = points[index];
      final next = points[(index + 1) % 10];
      final start = Offset.lerp(point, previous, .13)!;
      final end = Offset.lerp(point, next, .13)!;
      if (index == 0) { path.moveTo(start.dx, start.dy); }
      else { path.lineTo(start.dx, start.dy); }
      path.quadraticBezierTo(point.dx, point.dy, end.dx, end.dy);
    }
    return path..close();
  }

  void _sparkle(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(center.dx + 2, center.dy - 2, center.dx + radius, center.dy)
      ..quadraticBezierTo(center.dx + 2, center.dy + 2, center.dx, center.dy + radius)
      ..quadraticBezierTo(center.dx - 2, center.dy + 2, center.dx - radius, center.dy)
      ..quadraticBezierTo(center.dx - 2, center.dy - 2, center.dx, center.dy - radius);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HappyStarPainter oldDelegate) => progress != oldDelegate.progress || dark != oldDelegate.dark;
}
