import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../desktop_window.dart';
import '../sync_core.dart';
import '../task_dates.dart';
import '../workbench_queries.dart';
import 'calendar_screen.dart';
import 'achievements_screen.dart';
import 'conflict_dialog.dart';
import 'daily_celebration_dialog.dart';
import 'settings_screen.dart';
import 'task_editor.dart';
import 'task_board_view.dart';
import 'task_matrix_view.dart';
import 'task_detail_pane.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('桌面组件打开失败，请重试')));
      }
    }
  }

  void _newTask() => showTaskEditor(
    context,
    widget.controller,
    listName: _selectedList,
    initialDueDate: _newDueDate,
  );

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
    if (!mounted ||
        _celebrationScheduled ||
        _celebrationShowing ||
        widget.controller.pendingDailyCelebration == null) {
      return;
    }
    _celebrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _celebrationScheduled = false;
      if (!mounted || _celebrationShowing || widget.controller.editing) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      final pendingAtStart = widget.controller.pendingDailyCelebration;
      _celebrationShowing = true;
      try {
        if (!await DesktopWindow.isMainVisible() ||
            !mounted ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        final celebration = await widget.controller.takeDailyCelebration();
        if (celebration != null &&
            mounted &&
            ModalRoute.of(context)?.isCurrent == true &&
            (WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed)) {
          await showDailyCelebration(context, celebration);
        }
      } finally {
        _celebrationShowing = false;
        // A new day may complete while an older claim or dialog is finishing.
        // Retry only a different event, never loop on the same hidden card.
        if (mounted &&
            !identical(
              widget.controller.pendingDailyCelebration,
              pendingAtStart,
            )) {
          _scheduleCelebration();
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_scheduleCelebration);
    dailyCelebrationRouteObserver.unsubscribe(this);
    _search.dispose();
    _quickTitle.dispose();
    _quickFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.onResume();
      _scheduleCelebration();
    }
  }

  SmartTaskView _smartView = SmartTaskView.all;
  String _presentation = 'list';
  int? _priorityFilter;
  String? _selectedTaskId;
  bool _detailVisible = true;
  final _quickTitle = TextEditingController();
  final _quickFocus = FocusNode();
  final _searchFocus = FocusNode();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _quickSaving = false;

  bool get _taskPage => _page <= 2;

  void _selectPage(int index) {
    setState(() {
      _page = index;
      _selectedList = null;
      _selectedTaskId = null;
      _smartView = index == 1
          ? SmartTaskView.today
          : index == 2
          ? SmartTaskView.completed
          : SmartTaskView.all;
    });
  }

  void _selectSmart(SmartTaskView view, {String? listName}) {
    setState(() {
      _page = view == SmartTaskView.today
          ? 1
          : view == SmartTaskView.completed
          ? 2
          : 0;
      _smartView = view;
      _selectedList = listName;
      _selectedTaskId = null;
    });
  }

  String get _today => dateKey(DateTime.now());

  List<Task> _visibleTasks() => queryWorkbenchTasks(
    widget.controller.tasks,
    view: _smartView,
    query: _search.text,
    listName: _selectedList,
    priority: _priorityFilter,
    sort: _sort,
  );

  List<String> get _lists {
    final values =
        widget.controller.tasks
            .where((task) => !task.deleted)
            .map((task) => task.listName)
            .where((name) => name.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    values.remove('收件箱');
    return ['收件箱', ...values];
  }

  String get _heading {
    if (_selectedList != null) return _selectedList!;
    if (!_taskPage) return _titles[_page];
    return switch (_smartView) {
      SmartTaskView.all => '全部待办',
      SmartTaskView.inbox => '收件箱',
      SmartTaskView.today => '今天',
      SmartTaskView.nextSevenDays => '最近 7 天',
      SmartTaskView.completed => '已完成',
      SmartTaskView.important => '重要待办',
      SmartTaskView.overdue => '已逾期',
      SmartTaskView.unscheduled => '未安排',
    };
  }

  String? get _newDueDate => _page == 3 && _calendarDate != null
      ? dateKey(_calendarDate!)
      : _smartView == SmartTaskView.today && _taskPage
      ? _today
      : null;

  void _editTask(Task task) {
    if (widget.controller.conflicts.any((item) => item.taskId == task.id)) {
      showConflictDialog(context, widget.controller);
      return;
    }
    showTaskEditor(context, widget.controller, task: task);
  }

  Future<void> _quickAdd() async {
    final title = _quickTitle.text.trim();
    if (title.isEmpty || _quickSaving || widget.controller.editing) return;
    setState(() => _quickSaving = true);
    final saved = await widget.controller.saveTask(
      TaskDraft(
        title: title,
        listName: _selectedList ?? '收件箱',
        dueDate: _newDueDate,
        priority: _smartView == SmartTaskView.important
            ? 1
            : _priorityFilter ?? 0,
      ),
    );
    if (!mounted) return;
    setState(() {
      _quickSaving = false;
      if (saved) _quickTitle.clear();
    });
    if (saved) {
      _quickFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已添加，离线也能保存'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条待办？'),
        content: Text('“${task.title}”会从本机移除，并在下一次同步时从其他设备移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留'),
          ),
          FilledButton(
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          if (widget.controller.editing) return;
          if (_taskPage) {
            _quickFocus.requestFocus();
          } else {
            _newTask();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          if (_taskPage) {
            _searchFocus.requestFocus();
          } else {
            _selectPage(0);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _taskPage) _searchFocus.requestFocus();
            });
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          setState(() {
            _search.clear();
            _selectedTaskId = null;
          });
          FocusScope.of(context).unfocus();
        },
      },
      child: Focus(
        autofocus: true,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 1000 && constraints.maxHeight >= 500;
              final canShowDetails =
                  wide && constraints.maxWidth >= 1220 && _taskPage;
              final details = canShowDetails && _detailVisible;
              final colors = Theme.of(context).colorScheme;
              final tasks = _visibleTasks();
              Task? selected;
              for (final task in widget.controller.tasks) {
                if (task.id == _selectedTaskId && !task.deleted) {
                  selected = task;
                }
              }
              return Scaffold(
                key: _scaffoldKey,
                drawer: wide
                    ? null
                    : Drawer(child: SafeArea(child: _sidebar(drawer: true))),
                body: SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide) ...[_rail(), _sidebar()],
                      Expanded(
                        child: ColoredBox(
                          color: colors.surface,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _header(wide),
                              if (widget.controller.error != null)
                                _errorBanner(),
                              if (_page == 5)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: AchievementsScreen(
                                      controller: widget.controller,
                                    ),
                                  ),
                                )
                              else if (_page == 4)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: SettingsScreen(
                                      controller: widget.controller,
                                    ),
                                  ),
                                )
                              else if (_page == 3)
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: wide ? 20 : 10,
                                    ),
                                    child: CalendarScreen(
                                      controller: widget.controller,
                                      initialDate: _calendarDate,
                                      initialUnscheduled: _calendarDate == null,
                                      onDateSelected: (date) =>
                                          _calendarDate = date,
                                    ),
                                  ),
                                )
                              else ...[
                                _taskToolbar(tasks.length),
                                _quickEntry(),
                                Expanded(
                                  child: _presentation == 'board'
                                      ? TaskBoardView(
                                          controller: widget.controller,
                                          tasks: tasks,
                                          onEdit: _editTask,
                                        )
                                      : _presentation == 'matrix'
                                      ? TaskMatrixView(
                                          controller: widget.controller,
                                          tasks: tasks,
                                          onEdit: _editTask,
                                        )
                                      : tasks.isEmpty
                                      ? _emptyState()
                                      : ListView.separated(
                                          key: const ValueKey(
                                            'workbench-task-list',
                                          ),
                                          padding: EdgeInsets.fromLTRB(
                                            wide ? 22 : 12,
                                            0,
                                            wide ? 22 : 12,
                                            96,
                                          ),
                                          itemCount: tasks.length,
                                          separatorBuilder: (_, index) =>
                                              Divider(
                                                height: 1,
                                                indent: 42,
                                                color: colors.outlineVariant
                                                    .withValues(alpha: 0.5),
                                              ),
                                          itemBuilder: (context, index) {
                                            final task = tasks[index];
                                            final conflict = widget
                                                .controller
                                                .conflicts
                                                .any(
                                                  (item) =>
                                                      item.taskId == task.id,
                                                );
                                            return _WorkbenchTaskRow(
                                              task: task,
                                              today: _today,
                                              conflict: conflict,
                                              selected:
                                                  details &&
                                                  selected?.id == task.id,
                                              busy: widget.controller.editing,
                                              onToggle: () => widget.controller
                                                  .setCompleted(
                                                    task.id,
                                                    !task.completed,
                                                  ),
                                              onEdit: () => _editTask(task),
                                              onDelete: () => _deleteTask(task),
                                              onSelect: canShowDetails
                                                  ? () => setState(() {
                                                      _selectedTaskId = task.id;
                                                      _detailVisible = true;
                                                    })
                                                  : null,
                                              onConflict: () =>
                                                  showConflictDialog(
                                                    context,
                                                    widget.controller,
                                                  ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (details)
                        TaskDetailPane(
                          controller: widget.controller,
                          task: selected,
                          onEdit: () {
                            if (selected != null) _editTask(selected);
                          },
                          onDelete: () {
                            if (selected != null) _deleteTask(selected);
                          },
                          onClose: () => setState(() {
                            _selectedTaskId = null;
                            _detailVisible = false;
                          }),
                        ),
                    ],
                  ),
                ),
                floatingActionButton: !wide && _taskPage
                    ? FloatingActionButton.extended(
                        onPressed: widget.controller.editing ? null : _newTask,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新建待办'),
                      )
                    : null,
                bottomNavigationBar: wide
                    ? null
                    : NavigationBar(
                        height: 68,
                        selectedIndex: _page == 5 ? 0 : _page,
                        onDestinationSelected: _selectPage,
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.checklist_rounded),
                            label: '待办',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.wb_sunny_outlined),
                            label: '今天',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.task_alt_rounded),
                            label: '已完成',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.calendar_month_outlined),
                            label: '日历',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.settings_outlined),
                            label: '设置',
                          ),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _rail() {
    final colors = Theme.of(context).colorScheme;
    Widget item(IconData icon, String label, bool selected, VoidCallback tap) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: IconButton.filledTonal(
            tooltip: label,
            onPressed: tap,
            style: IconButton.styleFrom(
              backgroundColor: selected
                  ? colors.primaryContainer
                  : Colors.transparent,
              foregroundColor: selected
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
            icon: Icon(icon, size: 23),
          ),
        );
    return Container(
      width: 62,
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: colors.primary,
            child: Icon(
              Icons.done_all_rounded,
              color: colors.onPrimary,
              size: 21,
            ),
          ),
          const SizedBox(height: 28),
          item(
            Icons.checklist_rounded,
            '待办工作台',
            _taskPage,
            () => _selectPage(0),
          ),
          item(
            Icons.calendar_month_outlined,
            '日历',
            _page == 3,
            () => _selectPage(3),
          ),
          item(
            Icons.workspace_premium_outlined,
            '成就',
            _page == 5,
            () => _selectPage(5),
          ),
          const Spacer(),
          if (DesktopWindow.supported)
            item(
              Icons.picture_in_picture_alt_rounded,
              '桌面小组件',
              false,
              _openWidget,
            ),
          item(Icons.settings_outlined, '设置', _page == 4, () => _selectPage(4)),
        ],
      ),
    );
  }

  Widget _sidebar({bool drawer = false}) {
    final colors = Theme.of(context).colorScheme;
    void choose(VoidCallback action) {
      action();
      if (drawer) Navigator.of(context).pop();
    }

    int count(SmartTaskView view, {String? name}) => queryWorkbenchTasks(
      widget.controller.tasks,
      view: view,
      listName: name,
    ).length;
    Widget smart(String label, IconData icon, SmartTaskView view) => _navItem(
      label,
      icon,
      _taskPage && _smartView == view && _selectedList == null,
      count(view),
      () => choose(() => _selectSmart(view)),
    );
    return Container(
      width: drawer ? null : 210,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '私有待办',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 22),
            child: Text(
              '专注眼前，安排未来',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                smart('收件箱', Icons.inbox_outlined, SmartTaskView.inbox),
                smart('今天', Icons.wb_sunny_outlined, SmartTaskView.today),
                smart(
                  '最近 7 天',
                  Icons.date_range_outlined,
                  SmartTaskView.nextSevenDays,
                ),
                smart('全部待办', Icons.checklist_rounded, SmartTaskView.all),
                smart('重要待办', Icons.flag_outlined, SmartTaskView.important),
                smart('已逾期', Icons.event_busy_outlined, SmartTaskView.overdue),
                smart(
                  '未安排',
                  Icons.event_available_outlined,
                  SmartTaskView.unscheduled,
                ),
                smart('已完成', Icons.task_alt_rounded, SmartTaskView.completed),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 10, 10),
                  child: Text(
                    '我的清单',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final list in _lists.where((name) => name != '收件箱'))
                  _navItem(
                    list,
                    Icons.tag_rounded,
                    _selectedList == list,
                    count(SmartTaskView.all, name: list),
                    () => choose(
                      () => _selectSmart(SmartTaskView.all, listName: list),
                    ),
                  ),
                if (drawer) ...[
                  const Divider(height: 30),
                  _navItem(
                    '成就',
                    Icons.workspace_premium_outlined,
                    _page == 5,
                    null,
                    () => choose(() => _selectPage(5)),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 20),
          _navItem(
            '连接设置',
            Icons.settings_outlined,
            _page == 4,
            null,
            () => choose(() => _selectPage(4)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 2),
            child: Text(
              widget.controller.isConfigured ? '数据保存在你的 NAS' : '本机离线模式',
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    String label,
    IconData icon,
    bool selected,
    int? count,
    VoidCallback onTap,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.7)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count != null && count > 0)
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool wide) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: EdgeInsets.fromLTRB(wide ? 24 : 6, 8, wide ? 20 : 10, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(
        children: [
          if (!wide)
            IconButton(
              tooltip: '清单与智能视图',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded, size: 23),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                _syncStatus(),
              ],
            ),
          ),
          if (wide && _taskPage || _page == 3)
            FilledButton.icon(
              onPressed: widget.controller.editing ? null : _newTask,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建待办'),
            ),
        ],
      ),
    );
  }

  Widget _syncStatus() {
    final controller = widget.controller;
    final colors = Theme.of(context).colorScheme;
    final conflict = controller.conflicts.isNotEmpty;
    final label = conflict
        ? '${controller.conflicts.length} 项需要选择版本'
        : controller.syncing
        ? '正在与 NAS 同步'
        : !controller.isConfigured
        ? '待办已保存在本机'
        : controller.pendingCount > 0
        ? '${controller.pendingCount} 项等待同步'
        : controller.error != null
        ? '同步暂未完成'
        : controller.lastSyncedAt == null
        ? '等待首次同步'
        : '已与 NAS 同步';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        if (conflict) {
          showConflictDialog(context, controller);
        } else if (!controller.isConfigured) {
          _selectPage(4);
        } else if (!controller.busy) {
          controller.sync();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              conflict
                  ? Icons.info_outline_rounded
                  : controller.syncing
                  ? Icons.sync_rounded
                  : Icons.cloud_done_outlined,
              size: 12,
              color: conflict ? colors.error : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: conflict ? colors.error : colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.chevron_right_rounded,
              size: 12,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.errorContainer,
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.controller.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.onErrorContainer),
            ),
          ),
          IconButton(
            tooltip: '收起提示',
            onPressed: widget.controller.clearError,
            icon: const Icon(Icons.close_rounded, size: 17),
          ),
        ],
      ),
    );
  }

  Widget _taskToolbar(int count) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 42,
            child: TextField(
              key: const ValueKey('workbench-search'),
              controller: _search,
              focusNode: _searchFocus,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索待办、备注或清单',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close_rounded, size: 17),
                      ),
                fillColor: colors.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 11),
                    ),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 'list',
                      icon: Icon(Icons.format_list_bulleted_rounded, size: 15),
                      label: Text('列表'),
                    ),
                    ButtonSegment(
                      value: 'board',
                      icon: Icon(Icons.view_kanban_outlined, size: 15),
                      label: Text('看板'),
                    ),
                    ButtonSegment(
                      value: 'matrix',
                      icon: Icon(Icons.grid_view_rounded, size: 15),
                      label: Text('四象限'),
                    ),
                  ],
                  selected: {_presentation},
                  onSelectionChanged: (value) =>
                      setState(() => _presentation = value.first),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: '排序与筛选',
                icon: const Icon(Icons.tune_rounded, size: 20),
                onSelected: (value) => setState(() {
                  if (value.startsWith('sort:')) _sort = value.substring(5);
                  if (value.startsWith('priority:')) {
                    _priorityFilter = int.tryParse(value.substring(9));
                  }
                  if (value.startsWith('list:')) {
                    _selectedList = value.length == 5
                        ? null
                        : value.substring(5);
                  }
                }),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('排序', style: TextStyle(fontSize: 11)),
                  ),
                  CheckedPopupMenuItem(
                    value: 'sort:due',
                    checked: _sort == 'due',
                    child: const Text('截止日期优先'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'sort:priority',
                    checked: _sort == 'priority',
                    child: const Text('优先级优先'),
                  ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem(
                    value: 'priority:',
                    checked: _priorityFilter == null,
                    child: const Text('所有优先级'),
                  ),
                  for (var index = 0; index < 3; index++)
                    CheckedPopupMenuItem(
                      value: 'priority:$index',
                      checked: _priorityFilter == index,
                      child: Text(['普通', '较高', '紧急'][index]),
                    ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem(
                    value: 'list:',
                    checked: _selectedList == null,
                    child: const Text('所有清单'),
                  ),
                  for (final name in _lists)
                    CheckedPopupMenuItem(
                      value: 'list:$name',
                      checked: _selectedList == name,
                      child: Text(name),
                    ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 3),
            child: Row(
              children: [
                Text(
                  '$count 项待办',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (_priorityFilter != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    ['普通', '较高', '紧急'][_priorityFilter!],
                    style: TextStyle(fontSize: 10, color: colors.primary),
                  ),
                  InkWell(
                    onTap: () => setState(() => _priorityFilter = null),
                    child: const Icon(Icons.close_rounded, size: 13),
                  ),
                ],
                const Spacer(),
                Text(
                  _sort == 'priority' ? '优先级优先' : '截止日期优先',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickEntry() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: TextField(
        key: const ValueKey('workbench-quick-add'),
        controller: _quickTitle,
        focusNode: _quickFocus,
        enabled: !_quickSaving,
        maxLength: 200,
        onSubmitted: (_) => _quickAdd(),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: _smartView == SmartTaskView.today
              ? '添加今天的待办，按回车保存'
              : '添加待办，按回车保存',
          hintStyle: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          counterText: '',
          prefixIcon: Icon(Icons.add_rounded, size: 20, color: colors.primary),
          suffixIcon: IconButton(
            tooltip: '快速添加',
            onPressed: widget.controller.editing || _quickSaving
                ? null
                : _quickAdd,
            icon: _quickSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.subdirectory_arrow_left_rounded,
                    color: colors.onSurfaceVariant,
                    size: 18,
                  ),
          ),
          isDense: true,
          filled: true,
          fillColor: colors.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      ),
    );
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
        : _smartView != SmartTaskView.all
        ? '这里暂时没有待办'
        : '从一件小事开始';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                searching ? Icons.search_off_rounded : Icons.checklist_rounded,
                size: 28,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 9),
            Text(
              searching ? '换个关键词，或查看其他清单。' : '写下下一步，给重要的事留一点空间。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchTaskRow extends StatelessWidget {
  const _WorkbenchTaskRow({
    required this.task,
    required this.today,
    required this.conflict,
    required this.busy,
    required this.selected,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onConflict,
    this.onSelect,
  });
  final Task task;
  final String today;
  final bool conflict;
  final bool busy;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onConflict;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final priority = task.priority == 2
        ? const Color(0xffd64c55)
        : task.priority == 1
        ? const Color(0xffbb851b)
        : const Color(0xff64839d);
    final overdue =
        !task.completed &&
        task.dueDate != null &&
        task.dueDate!.compareTo(today) < 0;
    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: 0.4)
          : colors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: busy
            ? null
            : conflict
            ? onConflict
            : onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Checkbox(
                  value: task.completed,
                  activeColor: colors.primary,
                  side: BorderSide(color: priority, width: 1.5),
                  shape: const CircleBorder(),
                  onChanged: busy || conflict ? null : (_) => onToggle(),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: task.completed
                              ? colors.onSurfaceVariant
                              : colors.onSurface,
                          decoration: task.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (task.note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            task.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 9,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (task.dueDate != null)
                            Text(
                              task.dueDate == today ? '今天' : task.dueDate!,
                              style: TextStyle(
                                fontSize: 10,
                                color: overdue
                                    ? colors.error
                                    : task.dueDate == today
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          Text(
                            task.listName,
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          if (task.priority > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.flag_rounded,
                                  size: 11,
                                  color: priority,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  task.priority == 2 ? '紧急' : '较高',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: priority,
                                  ),
                                ),
                              ],
                            ),
                          if (conflict)
                            Text(
                              '需要选择版本',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.error,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (onSelect != null && !conflict)
                IconButton(
                  key: ValueKey('task-detail-${task.id}'),
                  tooltip: '查看详情',
                  onPressed: onSelect,
                  icon: Icon(
                    Icons.notes_rounded,
                    size: 17,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: '待办操作',
                enabled: !busy,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 19,
                  color: colors.onSurfaceVariant,
                ),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                  if (value == 'conflict') onConflict();
                },
                itemBuilder: (context) => conflict
                    ? const [
                        PopupMenuItem(value: 'conflict', child: Text('处理版本冲突')),
                      ]
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
