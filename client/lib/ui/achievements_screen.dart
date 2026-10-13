import 'dart:async';
import 'package:flutter/material.dart';
import '../achievement_core.dart';
import '../app_controller.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key, required this.controller, this.clock});
  final AppController controller;
  final DateTime Function()? clock;
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late int _year;
  late String _month;
  bool _followCurrent = true;
  Timer? _timer;
  DateTime get _today => (widget.clock ?? achievementToday)();
  @override
  void initState() {
    super.initState();
    _year = _today.year;
    _month = achievementMonth(_today);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_followCurrent) { _year = _today.year; _month = achievementMonth(_today); }
      });
    });
  }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  MonthAchievement _report(String month) => widget.controller.achievement?.settled
      .where((m) => m.month == month).firstOrNull ?? calculateAchievement(month, widget.controller.tasks);

  Color _color(MonthAchievement report) {
    final colors = Theme.of(context).colorScheme;
    if (!report.settled || report.status == 'empty') return colors.surfaceContainerHighest;
    return report.status == 'green' ? const Color(0xff347a54) : const Color(0xffab5151);
  }

  String _label(MonthAchievement report) {
    if (report.settled) return report.status == 'empty' ? '没有待办' : report.status == 'green' ? '全周达标' : '有周未达标';
    final current = achievementMonth(_today);
    if (report.month == current) return '进行中';
    if (report.month.compareTo(current) > 0) return '未开始';
    final start = widget.controller.achievement?.startMonth;
    return start == null || report.month.compareTo(start) < 0 ? '未记录' : '待结算';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.controller, builder: (context, _) {
    final colors = Theme.of(context).colorScheme;
    final report = _report(_month);
    final stars = widget.controller.achievement?.settled.where((m) => m.month.startsWith('$_year-'))
      .fold<int>(0, (sum, m) => sum + m.stars) ?? 0;
    return ListView(key: const ValueKey('achievements-scroll'), padding: const EdgeInsets.only(bottom: 24), children: [
      if (!widget.controller.achievementsSupported) Card(child: Padding(padding: const EdgeInsets.all(12),
        child: Text('先升级 NAS 成就服务并同步。当前可以查看本机进度，自动结算和清理需新版 NAS 服务。',
          key: const ValueKey('achievement-upgrade-notice'), style: TextStyle(color: colors.onSurfaceVariant)))),
      Row(children: [
        IconButton(tooltip: '上一年', onPressed: _year <= 1 ? null : () => setState(() {
          _followCurrent = false; _year--; _month = '${_year.toString().padLeft(4, '0')}-01';
        }), icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(child: Text('$_year 年', key: const ValueKey('achievement-year'), textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge)),
        IconButton(tooltip: '下一年', onPressed: _year >= 9998 ? null : () => setState(() {
          _followCurrent = false; _year++; _month = '${_year.toString().padLeft(4, '0')}-01';
        }), icon: const Icon(Icons.chevron_right_rounded)),
        TextButton(onPressed: () => setState(() { _followCurrent = true; _year = _today.year; _month = achievementMonth(_today); }), child: const Text('今年')),
      ]),
      Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('★ 已定格 $stars 颗星 · 每个有待办的周段完成率 ≥80% 得星',
        style: TextStyle(color: colors.onSurfaceVariant))),
      LayoutBuilder(builder: (context, constraints) => GridView.builder(shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(), itemCount: 12,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: constraints.maxWidth >= 600 ? 6 : 3,
          mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 64 + MediaQuery.textScalerOf(context).scale(28)),
        itemBuilder: (_, index) => _tile('${_year.toString().padLeft(4, '0')}-${(index + 1).toString().padLeft(2, '0')}'),
      )),
      const SizedBox(height: 12),
      Text('绿：每个有待办的周段都达标　红：存在未达标周段\n灰：无待办、进行中或未结算',
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      const SizedBox(height: 18),
      Text('${int.parse(_month.substring(5))}月 · ${_label(report)}', style: Theme.of(context).textTheme.titleMedium),
      Text('${report.completed}/${report.total} 项完成 · ★ ${report.stars} 颗${report.settled ? '' : '（月底定格）'}',
        key: const ValueKey('achievement-month-summary')),
      if (report.settled) Text('已归档清理 ${report.cleaned} 项，成就保留在 NAS。', style: TextStyle(color: colors.onSurfaceVariant)),
      const SizedBox(height: 10),
      for (final week in report.weeks) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(week.star ? Icons.star_rounded : Icons.star_outline_rounded,
            key: ValueKey('achievement-star-${week.start}'), color: week.star ? const Color(0xffd09a28) : colors.onSurfaceVariant),
            const SizedBox(width: 8), Expanded(child: Text('${week.start.substring(5).replaceAll('-', '/')} – ${week.end.substring(5).replaceAll('-', '/')}'))]),
          const SizedBox(height: 8),
          Text(week.total == 0 ? '无待办，不参与达标判定' : '${week.completed}/${week.total} 项 · ${(week.ratio * 100).round()}% · ${week.star ? '达标' : '未达标'}'),
          const SizedBox(height: 6), LinearProgressIndicator(value: week.ratio, borderRadius: BorderRadius.circular(6)),
        ],
      ))),
      const SizedBox(height: 12),
      Text('按安排日期统计，周一至周日，月初月末按本月内的周段。进行中的星星随待办变化，月底定格。\n'
        'NAS 按北京时间月底结算并归档清理该月已安排、有分类的所有待办（包括未完成）。收件箱、未分类和无日期待办保留。\n'
        '首次启用从当月开始。月末请及时同步；晚到的离线待办保留，历史结果不回改。跨年自动显示新一年，旧年可回看。',
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
    ]);
  });

  Widget _tile(String month) {
    final report = _report(month);
    final color = _color(report);
    final colors = Theme.of(context).colorScheme;
    final foreground = report.settled && report.status != 'empty' ? Colors.white : colors.onSurface;
    return Material(key: ValueKey('achievement-month-$month'), color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(
        color: month == _month ? colors.primary : Colors.transparent, width: 2)),
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => setState(() => _month = month),
        child: Padding(padding: const EdgeInsets.all(8), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${int.parse(month.substring(5))}月', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, color: foreground)),
          const SizedBox(height: 4), Text(_label(report), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: foreground)),
          Text('★ ${report.stars}', style: TextStyle(fontSize: 11, color: foreground)),
        ])),
      ));
  }
}
