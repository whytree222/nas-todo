import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../desktop_window.dart';
import '../task_dates.dart';
import 'agenda_task.dart';
import 'task_editor.dart';

class DesktopTodoScreen extends StatefulWidget {
  const DesktopTodoScreen({super.key, required this.controller, required this.onExpand});
  final AppController controller;
  final Future<void> Function() onExpand;

  @override
  State<DesktopTodoScreen> createState() => _DesktopTodoScreenState();
}

class _DesktopTodoScreenState extends State<DesktopTodoScreen> {
  bool _pinned = false;
  bool _unscheduled = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _pin() async {
    try {
      await DesktopWindow.setPinned(!_pinned);
      if (mounted) setState(() => _pinned = !_pinned);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('置顶失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final now = DateTime.now();
      final today = dateKey(now);
      final tasks = tasksOnDate(controller.tasks, _unscheduled ? null : today);
      final overdue = controller.tasks.where((task) => !task.deleted && !task.completed &&
          task.dueDate != null && task.dueDate!.compareTo(today) < 0).length;
      return Scaffold(body: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(children: [
          Row(children: [
            Expanded(child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) { unawaited(DesktopWindow.startDrag()); },
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('${now.month}月${now.day}日 · 私有待办',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
            )),
            IconButton(tooltip: _pinned ? '取消置顶' : '置顶', onPressed: _pin,
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18)),
            IconButton(tooltip: '打开主界面', onPressed: widget.onExpand,
              icon: const Icon(Icons.open_in_full_rounded, size: 18)),
          ]),
          Row(children: [
            ChoiceChip(label: const Text('今天'), selected: !_unscheduled,
              onSelected: (_) => setState(() => _unscheduled = false)),
            const SizedBox(width: 6),
            ChoiceChip(label: const Text('未安排'), selected: _unscheduled,
              onSelected: (_) => setState(() => _unscheduled = true)),
            const Spacer(),
            IconButton(tooltip: '新建待办', onPressed: controller.editing ? null : () =>
              showTaskEditor(context, controller, initialDueDate: _unscheduled ? null : today),
              icon: const Icon(Icons.add_rounded)),
          ]),
          Expanded(child: tasks.isEmpty ? const Center(child: Text('暂时没有待办')) : ListView(
            children: [for (final task in tasks) AgendaTask(task: task, controller: controller)],
          )),
          if (controller.error != null)
            Text(controller.error!, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)),
          Row(children: [
            Expanded(child: Text(controller.conflicts.isNotEmpty ? '有版本冲突，请打开主界面处理' :
              controller.pendingCount > 0 ? '${controller.pendingCount}项等待同步' :
              controller.isConfigured ? '已保存 · ${overdue > 0 ? '$overdue 项逾期' : 'NAS 已配置'}' : '本机离线模式',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
            IconButton(tooltip: '同步', onPressed: controller.busy ? null : controller.sync,
              icon: controller.syncing ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded, size: 18)),
          ]),
        ]),
      )));
    },
  );
}
