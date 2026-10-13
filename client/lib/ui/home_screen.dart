import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../desktop_window.dart';
import '../sync_core.dart';
import '../task_dates.dart';
import 'calendar_screen.dart';
import 'achievements_screen.dart';
import 'conflict_dialog.dart';
import 'daily_celebration_dialog.dart';
import 'settings_screen.dart';
import 'task_editor.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, RouteAware {
  final _search = TextEditingController();
  int _page = 0;
  String? _selectedList;
  String _sort = 'due';
  bool _celebrationScheduled = false;
  bool _celebrationShowing = false;
  ModalRoute<dynamic>? _observedRoute;
  static const _titles = ['全部待办', '今天', '已完成', '日历', '连接设置', '成就'];
  DateTime? _calendarDate = DateTime.now();
  Future<void> _openWidget() async {
    try {
      await DesktopWindow.openWidget();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('桌面组件打开失败，请重试')));
      }
    }
  }

  void _newTask() => showTaskEditor(context, widget.controller,
    listName: _selectedList,
    initialDueDate: _page == 3 && _calendarDate != null ? dateKey(_calendarDate!) : null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_scheduleCelebration);
    _scheduleCelebration();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _observedRoute) {
      dailyCelebrationRouteObserver.unsubscribe(this);
      _observedRoute = route;
      if (route != null) dailyCelebrationRouteObserver.subscribe(this, route);
    }
    _scheduleCelebration();
  }

  @override
  void didPopNext() => _scheduleCelebration();

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleCelebration);
      widget.controller.addListener(_scheduleCelebration);
      _scheduleCelebration();
    }
  }

  void _scheduleCelebration() {
    if (!mounted || _celebrationScheduled || _celebrationShowing ||
        widget.controller.pendingDailyCelebration == null) return;
    _celebrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _celebrationScheduled = false;
      if (!mounted || _celebrationShowing || widget.controller.editing) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _celebrationShowing = true;
      try {
        if (!await DesktopWindow.isMainVisible() || !mounted ||
            ModalRoute.of(context)?.isCurrent != true) return;
        final celebration = await widget.controller.takeDailyCelebration();
        if (celebration != null && mounted && ModalRoute.of(context)?.isCurrent == true &&
            (WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)) {
          await showDailyCelebration(context, celebration);
        }
      } finally {
        _celebrationShowing = false;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_scheduleCelebration);
    dailyCelebrationRouteObserver.unsubscribe(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.onResume();
      _scheduleCelebration();
    }
  }

  void _selectPage(int index) {
    setState(() {
      _page = index;
      _selectedList = null;
    });
  }

  String get _today {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  List<Task> _visibleTasks() {
    final query = _search.text.trim().toLowerCase();
    final tasks = widget.controller.tasks.where((task) {
      if (task.deleted) return false;
      if (_page == 2 ? !task.completed : task.completed) return false;
      if (_page == 1 && task.dueDate != _today) return false;
      if (_selectedList != null && task.listName != _selectedList) return false;
      return query.isEmpty ||
          '${task.title}\n${task.note}\n${task.listName}'.toLowerCase().contains(query);
    }).toList();
    tasks.sort((a, b) {
      final dueOrder = (a.dueDate ?? '9999-12-31').compareTo(b.dueDate ?? '9999-12-31');
      final priorityOrder = b.priority.compareTo(a.priority);
      final order = _sort == 'priority'
          ? (priorityOrder != 0 ? priorityOrder : dueOrder)
          : (dueOrder != 0 ? dueOrder : priorityOrder);
      return order != 0 ? order : a.title.compareTo(b.title);
    });
    return tasks;
  }

  List<String> get _lists {
    final values = widget.controller.tasks.map((task) => task.listName).toSet().toList()..sort();
    if (!values.contains('收件箱')) values.insert(0, '收件箱');
    if (_selectedList != null && !values.contains(_selectedList)) values.add(_selectedList!);
    return values;
  }

  Future<void> _toggleTask(Task task) async {
    await widget.controller.setCompleted(task.id, !task.completed);
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条待办？'),
        content: Text('“${task.title}”会从本机移除，并在下一次同步时从其他设备移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('保留')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deleteTask(task.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900 && constraints.maxHeight >= 600;
          final compact = !wide && constraints.maxHeight < 650;
          final veryShort = !wide && constraints.maxHeight < 500;
          final tasks = _visibleTasks();
          return Scaffold(
            resizeToAvoidBottomInset: false,
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) _sidebar(),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1050),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(wide ? 36 : 20, wide ? 34 : compact ? 12 : 20, wide ? 36 : 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _header(wide, compact: compact),
                              SizedBox(height: compact ? 12 : 22),
                              _syncBanner(compact: compact),
                              if (widget.controller.error != null) ...[
                                SizedBox(height: compact ? 8 : 12),
                                _errorBanner(compact: compact),
                              ],
                              SizedBox(height: compact ? 12 : 22),
                              if (_page == 5)
                                Expanded(child: AchievementsScreen(controller: widget.controller))
                              else if (_page == 4)
                                Expanded(child: SettingsScreen(controller: widget.controller))
                              else if (_page == 3)
                                Expanded(child: CalendarScreen(controller: widget.controller,
                                  initialDate: _calendarDate,
                                  initialUnscheduled: _calendarDate == null,
                                  onDateSelected: (date) => _calendarDate = date))
                              else ...[
                                _toolbar(wide || constraints.maxWidth >= 600),
                                if (!veryShort) ...[
                                  SizedBox(height: compact ? 12 : 18),
                                  Row(
                                    children: [
                                      Text('${tasks.length} 项待办', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                                      const Spacer(),
                                      const Icon(Icons.sort_rounded, size: 17),
                                      const SizedBox(width: 8),
                                      DropdownButton<String>(
                                        value: _sort,
                                        underline: const SizedBox.shrink(),
                                        isDense: true,
                                        style: Theme.of(context).textTheme.bodySmall,
                                        items: const [
                                          DropdownMenuItem(value: 'due', child: Text('截止日期优先')),
                                          DropdownMenuItem(value: 'priority', child: Text('优先级优先')),
                                        ],
                                        onChanged: (value) => setState(() => _sort = value ?? 'due'),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: compact ? 10 : 14),
                                ] else
                                  const SizedBox(height: 10),
                                Expanded(
                                  child: tasks.isEmpty
                                      ? _emptyState()
                                      : ListView.separated(
                                          padding: const EdgeInsets.only(bottom: 100),
                                          itemCount: tasks.length,
                                          separatorBuilder: (_, index) => const SizedBox(height: 10),
                                          itemBuilder: (context, index) {
                                            final task = tasks[index];
                                            final conflict = widget.controller.conflicts.any((item) => item.taskId == task.id);
                                            return _TaskCard(
                                              task: task,
                                              today: _today,
                                              conflict: conflict,
                                              busy: widget.controller.editing,
                                              onToggle: () => _toggleTask(task),
                                              onEdit: () => showTaskEditor(context, widget.controller, task: task),
                                              onDelete: () => _deleteTask(task),
                                              onConflict: () => showConflictDialog(context, widget.controller),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: !wide && _page != 4 && _page != 3 && _page != 5
                ? FloatingActionButton.extended(
                    onPressed: widget.controller.editing
                        ? null
                        : _newTask,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新建待办'),
                  )
                : null,
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _page,
                    onDestinationSelected: _selectPage,
                    destinations: const [
                      NavigationDestination(icon: Icon(Icons.checklist_rounded), label: '待办'),
                      NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: '今天'),
                      NavigationDestination(icon: Icon(Icons.task_alt_rounded), label: '已完成'),
                      NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: '日历'),
                      NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
                      NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), label: '成就'),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _header(bool wide, {bool compact = false}) {
    final colors = Theme.of(context).colorScheme;
    final activeCount = widget.controller.tasks.where((task) => !task.completed).length;
    final completedCount = widget.controller.tasks.where((task) => task.completed).length;
    final now = DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact) ...[
                Text(
                  _page == 4 ? '你的数据，你的 NAS' : '${now.month}月${now.day}日 · 把时间留给重要的事',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                _selectedList ?? _titles[_page],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
              ),
              if (_page != 4 && _page != 5 && !compact) ...[
                const SizedBox(height: 8),
                Text('$activeCount 项进行中 · $completedCount 项已完成', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
              ],
            ],
          ),
        ),
        if (DesktopWindow.supported)
          IconButton(tooltip: '桌面小组件', onPressed: _openWidget,
            icon: const Icon(Icons.picture_in_picture_alt_rounded)),
        if ((wide && _page != 4 && _page != 5) || _page == 3) ...[
          SizedBox(width: wide ? 16 : 8),
          FilledButton.icon(
            onPressed: widget.controller.editing
                ? null
                : _newTask,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('新建待办'),
          ),
        ],
      ],
    );
  }

  Widget _sidebar() {
    final colors = Theme.of(context).colorScheme;
    final controller = widget.controller;
    return Container(
      width: 236,
      decoration: BoxDecoration(color: colors.surface, border: Border(right: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)))),
      padding: const EdgeInsets.fromLTRB(18, 30, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.done_all_rounded, color: colors.onPrimary, size: 23),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('私有待办', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('数据属于你', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          _navItem('全部待办', Icons.checklist_rounded, _page == 0 && _selectedList == null,
              controller.tasks.where((task) => !task.completed).length, () => _selectPage(0)),
          _navItem('今天', Icons.wb_sunny_outlined, _page == 1,
              controller.tasks.where((task) => !task.completed && task.dueDate == _today).length, () => _selectPage(1)),
          _navItem('已完成', Icons.task_alt_rounded, _page == 2,
              controller.tasks.where((task) => task.completed).length, () => _selectPage(2)),
          _navItem('日历', Icons.calendar_month_outlined, _page == 3, null, () => _selectPage(3)),
          _navItem('成就', Icons.workspace_premium_outlined, _page == 5, null, () => _selectPage(5)),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('我的清单', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: colors.onSurfaceVariant)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: _lists.map((list) => _navItem(
                list,
                list == '收件箱' ? Icons.inbox_outlined : Icons.folder_outlined,
                _selectedList == list,
                controller.tasks.where((task) => !task.completed && task.listName == list).length,
                () => setState(() {
                  _page = 0;
                  _selectedList = list;
                }),
              )).toList(),
            ),
          ),
          _navItem('连接设置', Icons.settings_outlined, _page == 4, null, () => _selectPage(4)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Icon(Icons.dns_outlined, color: colors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(controller.isConfigured ? 'NAS 已配置' : '本机离线模式', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(controller.pendingCount > 0 ? '${controller.pendingCount} 项等待同步' : '安卓 · Windows', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(String label, IconData icon, bool selected, int? count, VoidCallback onTap) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? colors.primaryContainer.withValues(alpha: 0.65) : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 21, color: selected ? colors.primary : colors.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text('$count', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _syncBanner({bool compact = false}) {
    final controller = widget.controller;
    final colors = Theme.of(context).colorScheme;
    final hasConflicts = controller.conflicts.isNotEmpty;
    final title = hasConflicts
        ? '${controller.conflicts.length} 项待办需要选择版本'
        : controller.syncing
            ? '正在与 NAS 同步'
            : !controller.isConfigured
                ? '待办已保存在本机'
                : controller.pendingCount > 0
                    ? '${controller.pendingCount} 项修改等待上传'
                    : controller.error != null
                        ? '暂时无法完成同步'
                        : controller.lastSyncedAt == null
                            ? '等待首次同步'
                            : '已与 NAS 同步';
    final subtitle = hasConflicts
        ? '本机和 NAS 的修改都已保留，处理后继续同步。'
        : !controller.isConfigured
            ? '连接你的 NAS，让安卓和 Windows 同步。'
            : controller.error != null || controller.pendingCount > 0
                ? '你可以继续离线编辑，连接恢复后再同步。'
                : controller.lastSyncedAt != null
                    ? formatSyncTime(controller.lastSyncedAt)
                    : '使用同一地址与令牌连接你的设备。';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, compact ? 8 : 14, 10, compact ? 8 : 14),
      decoration: BoxDecoration(
        color: hasConflicts ? colors.tertiaryContainer : colors.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          controller.syncing
              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary))
              : Icon(hasConflicts ? Icons.compare_arrows_rounded : Icons.cloud_done_outlined, size: 24, color: hasConflicts ? colors.onTertiaryContainer : colors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (!compact) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, height: 1.4)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (hasConflicts)
            TextButton(onPressed: controller.busy ? null : () => showConflictDialog(context, controller), child: const Text('处理'))
          else if (!controller.isConfigured)
            TextButton(onPressed: () => _selectPage(3), child: const Text('连接'))
          else
            IconButton(tooltip: '立即同步', onPressed: controller.busy ? null : controller.sync, icon: const Icon(Icons.sync_rounded, size: 22)),
        ],
      ),
    );
  }

  Widget _errorBanner({bool compact = false}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(color: colors.errorContainer.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 9), child: Icon(Icons.info_outline_rounded, size: 18, color: colors.error)),
          const SizedBox(width: 10),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Text(widget.controller.error!, maxLines: compact ? 2 : 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.5, color: colors.onErrorContainer)))),
          IconButton(tooltip: '收起提示', onPressed: widget.controller.clearError, icon: const Icon(Icons.close_rounded, size: 18)),
        ],
      ),
    );
  }

  Widget _toolbar(bool wide) {
    final colors = Theme.of(context).colorScheme;
    final search = TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: '搜索待办、备注或清单',
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(tooltip: '清除搜索', onPressed: () => setState(_search.clear), icon: const Icon(Icons.close_rounded, size: 18)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
      ),
    );
    final listFilter = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: colors.surface, border: Border.all(color: colors.outlineVariant), borderRadius: BorderRadius.circular(14)),
      child: DropdownButton<String>(
        value: _selectedList ?? '',
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem(value: '', child: Text('所有清单', style: TextStyle(fontSize: 13))),
          ..._lists.map((list) => DropdownMenuItem(value: list, child: Text(list, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))),
        ],
        onChanged: (value) => setState(() => _selectedList = value == '' ? null : value),
      ),
    );
    return wide
        ? Row(children: [Expanded(child: search), const SizedBox(width: 12), SizedBox(width: 180, child: listFilter)])
        : Column(children: [search, const SizedBox(height: 10), listFilter]);
  }

  Widget _emptyState() {
    final colors = Theme.of(context).colorScheme;
    final searching = _search.text.trim().isNotEmpty;
    final title = searching
        ? '没有找到匹配的待办'
        : _page == 2
            ? '还没有已完成的待办'
            : _page == 1
                ? '今天没有到期待办'
                : _selectedList != null
                    ? '这个清单还是空的'
                    : '从一件小事开始';
    final subtitle = searching
        ? '换个关键词，或查看其他清单。'
        : _page == 2
            ? '完成的每一件小事，都会在这里留下记录。'
            : _page == 1
                ? '设置截止日期后，当天的待办会出现在这里。'
                : '添加你的第一条待办，离线也可以保存。';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(color: colors.primaryContainer.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: Icon(searching ? Icons.search_off_rounded : _page == 2 ? Icons.task_alt_rounded : Icons.spa_outlined, size: 35, color: colors.primary),
            ),
            const SizedBox(height: 24),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant, height: 1.6, fontSize: 13)),
            if (!searching && _page == 0) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: widget.controller.editing ? null : () => showTaskEditor(context, widget.controller, listName: _selectedList),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加待办'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.today,
    required this.conflict,
    required this.busy,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onConflict,
  });
  final Task task;
  final String today;
  final bool conflict;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onConflict;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final overdue = !task.completed && task.dueDate != null && task.dueDate!.compareTo(today) < 0;
    final dueToday = task.dueDate == today;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.65))),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : conflict ? onConflict : onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 15, 7, 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: task.completed,
                onChanged: busy || conflict ? null : (_) => onToggle(),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: task.completed ? colors.onSurfaceVariant : colors.onSurface,
                          decoration: task.completed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (task.note.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(task.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant, height: 1.5)),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          _TaskTag(label: task.listName, icon: Icons.folder_outlined, color: colors.onSurfaceVariant, background: colors.surfaceContainerLow),
                          if (task.dueDate != null)
                            _TaskTag(
                              label: '${overdue ? '已逾期 · ' : dueToday ? '今天 · ' : ''}${task.dueDate}',
                              icon: Icons.calendar_today_outlined,
                              color: overdue ? colors.onErrorContainer : dueToday ? colors.primary : colors.onSurfaceVariant,
                              background: overdue ? colors.errorContainer : colors.surfaceContainerLow,
                            ),
                          if (task.priority > 0)
                            _TaskTag(
                              label: task.priority == 2 ? '紧急' : '较高',
                              icon: Icons.flag_outlined,
                              color: task.priority == 2 ? colors.onErrorContainer : colors.onTertiaryContainer,
                              background: task.priority == 2 ? colors.errorContainer : colors.tertiaryContainer,
                            ),
                          if (conflict)
                            _TaskTag(label: '需要选择版本', icon: Icons.compare_arrows_rounded, color: colors.onTertiaryContainer, background: colors.tertiaryContainer),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '待办操作',
                enabled: !busy,
                icon: Icon(Icons.more_horiz_rounded, color: colors.onSurfaceVariant),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                  if (value == 'conflict') onConflict();
                },
                itemBuilder: (context) => conflict
                    ? const [PopupMenuItem(value: 'conflict', child: Text('处理版本冲突'))]
                    : const [
                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskTag extends StatelessWidget {
  const _TaskTag({required this.label, required this.icon, required this.color, required this.background});
  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(7)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(child: Text(label, style: TextStyle(fontSize: 10, color: color), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
