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
      if (!mounted) {
        return;
      }
      setState(() {
        if (_followCurrent) {
          _year = _today.year;
          _month = achievementMonth(_today);
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  MonthAchievement _report(String month) =>
      widget.controller.achievement?.settled
          .where((m) => m.month == month)
          .firstOrNull ??
      calculateAchievement(
        month,
        widget.controller.tasks,
        habitPlans: widget.controller.habitAchievementPlans,
        checkins: widget.controller.habitCheckIns,
        through: DateTime(_today.year, _today.month, _today.day),
        includeHabits: true,
      );

  Color _color(MonthAchievement report) {
    final colors = Theme.of(context).colorScheme;
    if (!report.settled || report.status == 'empty') {
      return colors.surfaceContainerHighest;
    }
    return report.status == 'green'
        ? const Color(0xff347a54)
        : const Color(0xffab5151);
  }

  String _label(MonthAchievement report) {
    if (report.settled) {
      return report.status == 'empty'
          ? '没有计划'
          : report.status == 'green'
          ? '全周达标'
          : '有周未达标';
    }
    final current = achievementMonth(_today);
    if (report.month == current) {
      return '进行中';
    }
    if (report.month.compareTo(current) > 0) {
      return '未开始';
    }
    final start = widget.controller.achievement?.startMonth;
    return start == null || report.month.compareTo(start) < 0 ? '未记录' : '待结算';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final report = _report(_month);
      final stars =
          widget.controller.achievement?.settled
              .where((m) => m.month.startsWith('$_year-'))
              .fold<int>(0, (sum, m) => sum + m.stars) ??
          0;
      return ListView(
        key: const ValueKey('achievements-scroll'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (!widget.controller.habitAchievementsSupported)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '请升级 NAS 到 v0.11.0 成就服务并同步，启用习惯计划历史和双达标结算。当前显示本机进度，已结算历史不回改。',
                  key: const ValueKey('achievement-upgrade-notice'),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: '上一年',
                onPressed: _year <= 1
                    ? null
                    : () => setState(() {
                        _followCurrent = false;
                        _year--;
                        _month = '${_year.toString().padLeft(4, '0')}-01';
                      }),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '$_year 年',
                  key: const ValueKey('achievement-year'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '下一年',
                onPressed: _year >= 9998
                    ? null
                    : () => setState(() {
                        _followCurrent = false;
                        _year++;
                        _month = '${_year.toString().padLeft(4, '0')}-01';
                      }),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _followCurrent = true;
                  _year = _today.year;
                  _month = achievementMonth(_today);
                }),
                child: const Text('今年'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              '★ 已定格 $stars 颗星 · 待办与习惯分别 ≥80% 得星',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth >= 600 ? 6 : 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 64 + MediaQuery.textScalerOf(context).scale(28),
              ),
              itemBuilder: (_, index) => _tile(
                '${_year.toString().padLeft(4, '0')}-${(index + 1).toString().padLeft(2, '0')}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '绿：每个有计划的周段都达标　红：存在未达标周段\n灰：无计划、进行中或未结算',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Text(
            '${int.parse(_month.substring(5))}月 · ${_label(report)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '待办 ${report.taskCompleted}/${report.taskTotal} 项 · 习惯 ${report.habitCompleted}/${report.habitTotal} 天 · ★ ${report.stars} 颗${report.settled ? '' : '（月底定格）'}',
            key: const ValueKey('achievement-month-summary'),
          ),
          if (report.settled)
            Text(
              '已归档清理 ${report.cleaned} 项，成就保留在 NAS。',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          const SizedBox(height: 10),
          for (final week in report.weeks)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          week.star
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          key: ValueKey('achievement-star-${week.start}'),
                          color: week.star
                              ? const Color(0xffd09a28)
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${week.start.substring(5).replaceAll('-', '/')} – ${week.end.substring(5).replaceAll('-', '/')}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      week.total == 0
                          ? '无计划，不参与达标判定'
                          : week.star
                          ? '本周段达标'
                          : '本周段未达标',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      week.plannedTasks == 0
                          ? '待办：无安排，不参与'
                          : '待办：${week.completedTasks}/${week.plannedTasks} 项 · ${(week.taskRatio * 100).round()}%',
                    ),
                    if (week.plannedTasks > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(
                          value: week.taskRatio,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      week.rulesVersion == 1
                          ? '习惯：该历史月份沿用原待办规则'
                          : week.habitTotal == 0
                          ? '习惯：无计划日，不参与'
                          : '习惯：${week.habitCompleted}/${week.habitTotal} 天 · ${(week.habitRatio * 100).round()}%',
                    ),
                    if (week.habitTotal > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(
                          value: week.habitRatio,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '周一至周日分段，月初月末只算本月内日期。待办完成率和习惯达标率分别达到80%才得星；某类无计划时不参与。\n'
            '每个习惯的每个计划日最多计1天，次数目标当天达到才达标。休息日与未来日期不计入实时习惯分母；不是按点击次数计分。\n'
            '习惯计划、目标或删除从修改当天生效，以前日期保留原计划。已有习惯从NAS新规则启用日开始计，新增习惯从创建日开始计。月底定格，已结算月份不回算。\n'
            'NAS 按北京时间月底结算并归档清理该月已安排、有分类的所有待办（包括未完成）。收件箱、未分类和无日期待办保留。\n'
            '首次启用从当月开始。月末请及时同步；晚到的离线待办保留，历史结果不回改。跨年自动显示新一年，旧年可回看。',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      );
    },
  );

  Widget _tile(String month) {
    final report = _report(month);
    final color = _color(report);
    final colors = Theme.of(context).colorScheme;
    final foreground = report.settled && report.status != 'empty'
        ? Colors.white
        : colors.onSurface;
    return Material(
      key: ValueKey('achievement-month-$month'),
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: month == _month ? colors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _month = month;
          _followCurrent = month == achievementMonth(_today);
        }),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${int.parse(month.substring(5))}月',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _label(report),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: foreground),
              ),
              Text(
                '★ ${report.stars}',
                style: TextStyle(fontSize: 11, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
