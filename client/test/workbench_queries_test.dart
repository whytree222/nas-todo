import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/workbench_queries.dart';

Task _task(
  String id, {
  String? date,
  int priority = 0,
  bool completed = false,
  bool deleted = false,
  String list = '工作',
  String? title,
  String note = '',
  String updated = '',
}) => Task(
  id: id,
  title: title ?? id,
  note: note,
  listName: list,
  dueDate: date,
  priority: priority,
  completed: completed,
  deleted: deleted,
  updatedAt: updated,
);

void main() {
  final day = DateTime(2026, 12, 29, 23, 59);
  final tasks = [
    _task('past', date: '2026-12-28', priority: 2),
    _task('today', date: '2026-12-29', priority: 1),
    _task('tomorrow', date: '2026-12-30'),
    _task('weekEnd', date: '2027-01-04'),
    _task('later', date: '2027-01-05'),
    _task('undated', list: '收件箱'),
    _task('done', date: '2026-12-29', priority: 2, completed: true),
    _task('deleted', date: '2026-12-29', deleted: true),
  ];
  List<String> ids(SmartTaskView view) => queryWorkbenchTasks(
    tasks,
    view: view,
    now: day,
  ).map((task) => task.id).toList();

  test('Smart views exclude tombstones and separate completed work', () {
    expect(ids(SmartTaskView.all), [
      'today',
      'tomorrow',
      'weekEnd',
      'later',
      'undated',
    ]);
    expect(ids(SmartTaskView.completed), ['done']);
    expect(ids(SmartTaskView.today), ['today']);
    expect(ids(SmartTaskView.important), ['past', 'today']);
    expect(ids(SmartTaskView.overdue), ['past']);
    expect(ids(SmartTaskView.unscheduled), ['undated']);
  });

  test(
    'All hides overdue without deleting them or hiding them from their list',
    () {
      expect(
        queryWorkbenchTasks(
          tasks,
          view: SmartTaskView.all,
          now: day,
          listName: '工作',
        ).map((t) => t.id),
        contains('past'),
      );
      expect(ids(SmartTaskView.overdue), ['past']);
      expect(tasks.first.dueDate, '2026-12-28');
      expect(
        ids(SmartTaskView.all),
        containsAll(['today', 'tomorrow', 'undated']),
      );
      expect(
        queryWorkbenchTasks(
          tasks,
          view: SmartTaskView.all,
          now: DateTime(2026, 12, 30),
        ).map((t) => t.id),
        isNot(contains('today')),
      );
    },
  );

  test(
    'Next seven days includes today through day six across a year boundary',
    () {
      expect(ids(SmartTaskView.nextSevenDays), [
        'today',
        'tomorrow',
        'weekEnd',
      ]);
      final leap = queryWorkbenchTasks(
        [
          _task('leap', date: '2024-02-29'),
          _task('end', date: '2024-03-05'),
          _task('outside', date: '2024-03-06'),
        ],
        view: SmartTaskView.nextSevenDays,
        now: DateTime(2024, 2, 28, 23),
      );
      expect(leap.map((task) => task.id), ['leap', 'end']);
    },
  );

  test('Inbox groups existing uncategorized names without changing the stored names', () {
    final entries = [
      _task('a', list: '收件箱'),
      _task('b', list: ' 未分类 '),
      _task('c', list: ''),
      _task('d', list: '生活'),
    ];
    expect(
      queryWorkbenchTasks(
        entries,
        view: SmartTaskView.inbox,
      ).map((task) => task.id),
      ['a', 'b', 'c'],
    );
    expect(entries[1].listName, ' 未分类 ');
  });

  test('Search covers title, private note and list while combining exact list and priority filters', () {
    final entries = [
      _task('title', title: 'Read FLUTTER', list: '学习', priority: 1),
      _task('note', note: 'flutter notes', list: '学习', priority: 2),
      _task('list', list: 'Flutter', priority: 1),
    ];
    expect(
      queryWorkbenchTasks(
        entries,
        view: SmartTaskView.all,
        query: '  FLUTTER ',
      ).length,
      3,
    );
    expect(
      queryWorkbenchTasks(
        entries,
        view: SmartTaskView.all,
        query: 'flutter',
        listName: '学习',
        priority: 1,
      ).map((task) => task.id),
      ['title'],
    );
  });

  test('Sorts are deterministic and never reorder the input list', () {
    final entries = [
      _task(
        'z',
        title: 'Same',
        date: '2026-12-29',
        updated: '2026-12-29T00:00:00Z',
      ),
      _task(
        'a',
        title: 'Same',
        date: '2026-12-29',
        updated: '2026-12-30T00:00:00Z',
      ),
      _task('p', title: 'Last', priority: 2),
    ];
    expect(
      queryWorkbenchTasks(
        entries,
        view: SmartTaskView.all,
      ).map((task) => task.id),
      ['a', 'z', 'p'],
    );
    expect(
      queryWorkbenchTasks(
        entries,
        view: SmartTaskView.all,
        sort: 'priority',
      ).first.id,
      'p',
    );
    expect(
      queryWorkbenchTasks(
        entries,
        view: SmartTaskView.all,
        sort: 'title',
      ).first.id,
      'p',
    );
    expect(
      queryWorkbenchTasks(
        entries,
        view: SmartTaskView.all,
        sort: 'recent',
      ).first.id,
      'a',
    );
    expect(entries.map((task) => task.id), ['z', 'a', 'p']);
  });

  test('Due buckets partition every visible date without overlaps or missing undated tasks', () {
    final groups = groupWorkbenchTasksByDueDate(tasks, now: day);
    expect(groups[WorkbenchDueBucket.overdue]!.map((task) => task.id), [
      'past',
    ]);
    expect(groups[WorkbenchDueBucket.today]!.map((task) => task.id), [
      'done',
      'today',
    ]);
    expect(groups[WorkbenchDueBucket.tomorrow]!.map((task) => task.id), [
      'tomorrow',
    ]);
    expect(groups[WorkbenchDueBucket.nextSevenDays]!.map((task) => task.id), [
      'weekEnd',
    ]);
    expect(groups[WorkbenchDueBucket.later]!.map((task) => task.id), ['later']);
    expect(groups[WorkbenchDueBucket.unscheduled]!.map((task) => task.id), [
      'undated',
    ]);
    expect(groups.values.expand((entries) => entries).length, 7);
  });

  test(
    'Matrix importance uses priority and urgency uses today or overdue date',
    () {
      expect(
        taskMatrixQuadrant(
          _task('a', priority: 1, date: '2026-12-29'),
          now: day,
        ),
        MatrixQuadrant.importantUrgent,
      );
      expect(
        taskMatrixQuadrant(
          _task('b', priority: 2, date: '2026-12-30'),
          now: day,
        ),
        MatrixQuadrant.importantNotUrgent,
      );
      expect(
        taskMatrixQuadrant(_task('c', date: '2026-12-28'), now: day),
        MatrixQuadrant.notImportantUrgent,
      );
      expect(
        taskMatrixQuadrant(_task('d'), now: day),
        MatrixQuadrant.notImportantNotUrgent,
      );
    },
  );

  test('Matrix move previews preserve existing higher priority, overdue dates and future dates', () {
    final urgent = matrixPlacementFor(
      _task('a', priority: 2, date: '2026-12-28'),
      MatrixQuadrant.importantUrgent,
      now: day,
    );
    expect(
      [urgent.priority, urgent.dueDate, urgent.clearDueDate],
      [2, '2026-12-28', false],
    );
    final makeUrgent = matrixPlacementFor(
      _task('b', date: '2027-01-04'),
      MatrixQuadrant.importantUrgent,
      now: day,
    );
    expect(
      [makeUrgent.priority, makeUrgent.dueDate, makeUrgent.clearDueDate],
      [1, '2026-12-29', false],
    );
    final clear = matrixPlacementFor(
      _task('c', priority: 2, date: '2026-12-29'),
      MatrixQuadrant.notImportantNotUrgent,
      now: day,
    );
    expect(clear.priority, 0);
    expect(clear.clearDueDate, isTrue);
    final future = matrixPlacementFor(
      _task('d', priority: 1, date: '2027-01-04'),
      MatrixQuadrant.importantNotUrgent,
      now: day,
    );
    expect(
      [future.priority, future.dueDate, future.clearDueDate],
      [1, '2027-01-04', false],
    );
  });
}
