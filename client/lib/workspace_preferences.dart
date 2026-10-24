/// Device-only display preferences. They never alter task or NAS records.
class WorkspacePreferences {
  const WorkspacePreferences({
    this.matrixEnabled = false,
    this.page = 0,
    this.smartView = 'all',
    this.listName,
    this.tag,
    this.presentation = 'list',
    this.detailVisible = true,
    this.selectedTaskId,
    this.scrollOffset = 0,
    this.sort = 'due',
    this.priority,
  });
  final bool matrixEnabled;
  final int page;
  final String smartView;
  final String? listName, tag, selectedTaskId;
  final String presentation, sort;
  final bool detailVisible;
  final double scrollOffset;
  final int? priority;
  factory WorkspacePreferences.fromJson(Map<String, dynamic>? json) {
    final value = json ?? const <String, dynamic>{};
    final matrix = value['matrix_enabled'] == true;
    final offset = value['scroll_offset'];
    return WorkspacePreferences(
      matrixEnabled: matrix,
      page: const [0, 1, 2, 3, 4, 5, 6].contains(value['page'])
          ? value['page'] as int
          : 0,
      smartView: value['smart_view'] is String
          ? value['smart_view'] as String
          : 'all',
      listName: value['list_name'] as String?,
      tag: value['tag'] as String?,
      presentation: value['presentation'] == 'board'
          ? 'board'
          : value['presentation'] == 'matrix' && matrix
          ? 'matrix'
          : 'list',
      detailVisible: value['detail_visible'] != false,
      selectedTaskId: value['selected_task_id'] as String?,
      scrollOffset: offset is num && offset.isFinite && offset >= 0
          ? offset.toDouble()
          : 0,
      sort: value['sort'] == 'priority' ? 'priority' : 'due',
      priority: const [0, 1, 2].contains(value['priority'])
          ? value['priority'] as int
          : null,
    );
  }
  Map<String, dynamic> toJson() => {
    'matrix_enabled': matrixEnabled,
    'page': page,
    'smart_view': smartView,
    'list_name': listName,
    'tag': tag,
    'presentation': presentation,
    'detail_visible': detailVisible,
    'selected_task_id': selectedTaskId,
    'scroll_offset': scrollOffset,
    'sort': sort,
    'priority': priority,
  };
  WorkspacePreferences withChanges(Map<String, dynamic> changes) =>
      WorkspacePreferences.fromJson({...toJson(), ...changes});
}
