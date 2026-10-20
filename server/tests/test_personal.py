"""Personal collections, legacy-client compatibility and repeat atomicity."""
import copy
from contextlib import closing
import datetime as dt
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import ApiError, Config, SyncService, backup_database
from test_sync import TOKEN, operation


class PersonalTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=os.environ.get('NAS_TODO_TEST_TMP'))
        self.path = Path(self.directory.name) / 'todo.sqlite'
        self.today = dt.date(2026, 10, 1)
        self.service = SyncService(Config(self.path, TOKEN), clock=lambda: self.today)
        self.instance = self.tasks()['instance_id']

    def tearDown(self):
        self.directory.cleanup()

    def tasks(self, ops=(), *, defer=False, cursor=0):
        value = {'instance_id': getattr(self, 'instance', None), 'cursor': cursor, 'operations': list(ops)}
        if defer:
            value['defer_repeats'] = True
        return self.service.sync(value)

    def personal(self, ops=(), *, cursor=0, release=()):
        return self.service.sync_personal({'instance_id': self.instance, 'cursor': cursor,
            'operations': list(ops), 'release_tasks': list(release)})

    def op(self, kind, data, *, record_id=None, base=0, action='upsert'):
        return {'op_id': str(uuid.uuid4()), 'kind': kind, 'id': record_id or str(uuid.uuid4()),
                'base_version': base, 'action': action, 'data': data}

    def task(self, **kwargs):
        op = operation(**kwargs)
        return self.tasks([op])['results'][0]['task']

    def meta(self, task, *, parent=None, tags=None, repeat=None, base=0):
        return self.op('task_meta', {'parent_id': parent, 'tags': tags or [], 'repeat_rule': repeat}, record_id=task['id'], base=base)

    def rule(self, frequency='daily', interval=1, weekdays=None, month_day=None):
        return {'frequency': frequency, 'interval': interval, 'weekdays': weekdays or [], 'month_day': month_day}

    def test_habits_checkins_restart_retry_and_conflict(self):
        habit = self.op('habit', {'name': '阅读', 'goal_type': 'count', 'goal': 3, 'weekdays': [1, 2, 3, 4, 5]})
        result = self.personal([habit])
        self.assertEqual(result['results'][0]['status'], 'applied')
        checkin = self.op('habit_checkin', {'habit_id': habit['id'], 'date': '2026-10-01', 'value': 3}, record_id=habit['id'] + ':2026-10-01')
        first = self.personal([checkin])
        self.assertEqual(self.personal([checkin])['results'], first['results'])
        self.service = SyncService(Config(self.path, TOKEN), clock=lambda: self.today)
        stale = self.op('habit_checkin', {**checkin['data'], 'value': 2}, record_id=checkin['id'])
        conflict = self.personal([stale])['results'][0]
        self.assertEqual(conflict['status'], 'conflict')
        self.assertEqual(conflict['record']['data']['value'], 3)
        self.assertEqual(len(self.personal()['changes']), 2)

    def test_reused_personal_operation_rolls_back_whole_batch(self):
        habit = self.op('habit', {'name': '阅读', 'goal_type': 'bool', 'goal': 1, 'weekdays': [1]})
        self.personal([habit])
        altered = copy.deepcopy(habit)
        altered['data']['name'] = '不同内容'
        extra = self.op('habit', {**habit['data'], 'name': '不能写入'})
        with self.assertRaises(ApiError) as error:
            self.personal([extra, altered])
        self.assertEqual(error.exception.code, 'op_id_reused')
        self.assertEqual(len(self.personal()['changes']), 1)

    def test_legacy_task_write_does_not_erase_metadata(self):
        parent, child = self.task(title='父'), self.task(title='子')
        self.personal([self.meta(child, parent=parent['id'], tags=['阅读', '学习', '阅读'])])
        self.tasks([operation(task_id=child['id'], base=1, title='旧客户端改标题')])
        record = self.personal()['changes'][0]
        self.assertEqual(record['data']['parent_id'], parent['id'])
        self.assertEqual(record['data']['tags'], ['学习', '阅读'])

    def test_cycle_and_sixth_level_rejected_without_overwriting(self):
        tasks = [self.task(title=str(index)) for index in range(6)]
        self.personal([self.meta(tasks[index], parent=tasks[index - 1]['id']) for index in range(1, 5)])
        sixth = self.personal([self.meta(tasks[5], parent=tasks[4]['id'])])
        self.assertEqual(sixth['results'][0]['status'], 'conflict')
        cyclic = self.personal([self.meta(tasks[0], parent=tasks[4]['id'])])
        self.assertEqual(cyclic['results'][0]['status'], 'conflict')
        self.assertEqual(len(self.personal()['changes']), 4)

    def test_parent_delete_promotes_child_and_keeps_other_metadata(self):
        parent, child = self.task(title='父'), self.task(title='子', due_date=None)
        self.personal([self.meta(child, parent=parent['id'], tags=['保留'])])
        self.tasks([operation(task_id=parent['id'], base=1, action='delete')])
        record = self.personal()['changes'][0]
        self.assertIsNone(record['data']['parent_id'])
        self.assertEqual(record['data']['tags'], ['保留'])
        same_promotion = self.personal([self.meta(child, tags=['保留'], base=1)])['results'][0]
        self.assertEqual(same_promotion['status'], 'applied')
        self.assertEqual(same_promotion['record']['version'], record['version'])
        self.assertFalse(next(t for t in self.tasks()['changes'] if t['id'] == child['id'])['deleted'])

    def test_month_cleanup_archives_metadata_and_promotes_undated_child(self):
        parent = self.task(title='月末清理', list_name='工作', due_date='2026-10-01')
        child = self.task(title='不能清理', list_name='工作', due_date=None)
        self.personal([self.meta(parent, tags=['归档']), self.meta(child, parent=parent['id'])])
        self.today = dt.date(2026, 11, 1)
        self.service.settle_months()
        rows = self.personal()['changes']
        self.assertIsNone(next(r for r in rows if r['id'] == child['id'])['data']['parent_id'])
        with closing(sqlite3.connect(self.path)) as db:
            archived = json.loads(db.execute('SELECT task_json FROM achievement_archive WHERE task_id=?', (parent['id'],)).fetchone()[0])
        self.assertEqual(archived['personal_metadata']['tags'], ['归档'])

    def test_repeats_spawn_once_across_undo_recomplete_and_retry(self):
        source = self.task(due_date='2026-10-01')
        self.personal([self.meta(source, tags=['运动'], repeat=self.rule())])
        complete = operation(task_id=source['id'], base=1, completed=True, due_date='2026-10-01')
        first = self.tasks([complete])
        self.tasks([complete])
        successor = next(t for t in first['changes'] if t['id'] != source['id'])
        self.assertEqual(successor['due_date'], '2026-10-02')
        self.tasks([operation(task_id=source['id'], base=2, completed=False, due_date='2026-10-01')])
        self.tasks([operation(task_id=source['id'], base=3, completed=True, due_date='2026-10-01')])
        self.assertEqual(len(self.tasks()['changes']), 2)
        self.assertEqual(next(r for r in self.personal()['changes'] if r['id'] == successor['id'])['data']['tags'], ['运动'])

    def test_new_client_cancels_repeat_atomically_even_if_other_client_polls(self):
        source = self.task(due_date='2026-10-01')
        self.personal([self.meta(source, repeat=self.rule())])
        completed = operation(task_id=source['id'], base=1, completed=True, due_date='2026-10-01')
        self.tasks([completed], defer=True)
        self.assertEqual(len(self.tasks()['changes']), 1, 'Legacy poll cannot generate a deferred recurrence')
        self.personal([self.meta(source, base=1)], release=[source['id']])
        self.assertEqual(len(self.tasks()['changes']), 1)

    def test_date_and_rule_edit_use_latest_base_date_before_releasing(self):
        source = self.task(due_date='2026-10-01')
        self.personal([self.meta(source, repeat=self.rule())])
        self.tasks([operation(task_id=source['id'], base=1, completed=True, due_date='2026-10-20')], defer=True)
        result = self.personal([self.meta(source, base=1, repeat=self.rule(interval=3))], release=[source['id']])
        self.assertEqual(result['generated_tasks'][0]['due_date'], '2026-10-23')
        self.assertEqual(result['released_tasks'], [source['id']])

    def test_conflicted_metadata_keeps_repeat_deferred_until_explicit_resolution(self):
        source = self.task(due_date='2026-10-01')
        self.personal([self.meta(source, repeat=self.rule())])
        self.tasks([operation(task_id=source['id'], base=1, completed=True, due_date='2026-10-01')], defer=True)
        conflict = self.personal([self.meta(source, base=0)], release=[source['id']])
        self.assertEqual(conflict['results'][0]['status'], 'conflict')
        self.assertEqual(conflict['released_tasks'], [])
        self.assertEqual(len(self.tasks()['changes']), 1)
        resolved = self.personal([self.meta(source, base=1)], release=[source['id']])
        self.assertEqual(resolved['released_tasks'], [source['id']])
        self.assertEqual(resolved['generated_tasks'], [])

    def test_repeat_calendar_arithmetic_leap_month_and_week_interval(self):
        monthly = self.rule('monthly', month_day=31)
        feb = self.service._next_repeat_date(dt.date(2024, 1, 31), monthly)
        self.assertEqual(feb, dt.date(2024, 2, 29))
        self.assertEqual(self.service._next_repeat_date(feb, monthly), dt.date(2024, 3, 31))
        weekly = self.rule('weekly', interval=2, weekdays=[1, 5])
        self.assertEqual(self.service._next_repeat_date(dt.date(2026, 10, 5), weekly), dt.date(2026, 10, 9))
        self.assertEqual(self.service._next_repeat_date(dt.date(2026, 10, 9), weekly), dt.date(2026, 10, 19))

    def test_personal_data_capacity_and_wrong_identity_do_not_write(self):
        limited = SyncService(Config(self.path, TOKEN, max_data_bytes=20), clock=lambda: self.today)
        habit = self.op('habit', {'name': '阅读', 'goal_type': 'bool', 'goal': 1, 'weekdays': [1]})
        with self.assertRaises(ApiError):
            limited.sync_personal({'instance_id': self.instance, 'cursor': 0, 'operations': [habit]})
        with self.assertRaises(ApiError):
            self.service.sync_personal({'instance_id': str(uuid.uuid4()), 'cursor': 0, 'operations': [habit]})
        self.assertEqual(self.personal()['changes'], [])

    def test_database_reinitialize_and_backup_preserve_identity_versions_and_personal_data(self):
        source = self.task(title='旧数据')
        self.personal([self.meta(source, tags=['学习'])])
        self.service.initialize()
        self.assertEqual(self.tasks()['instance_id'], self.instance)
        self.assertEqual(self.tasks()['changes'][0]['version'], source['version'])
        target = Path(self.directory.name) / 'backup.sqlite'
        backup_database(self.path, target)
        restored = SyncService(Config(target, TOKEN), clock=lambda: self.today)
        response = restored.sync_personal({'instance_id': self.instance, 'cursor': 0, 'operations': []})
        self.assertEqual(response['changes'][0]['data']['tags'], ['学习'])

    def test_actual_legacy_schema_migrates_without_replacing_existing_tasks_or_identity(self):
        task = self.task(title='旧版待办', completed=True)
        with closing(sqlite3.connect(self.path)) as db:
            for table in ('personal_records', 'personal_operations', 'repeat_spawns', 'deferred_repeats'):
                db.execute('DROP TABLE ' + table)
            db.execute("DELETE FROM metadata WHERE key LIKE 'personal_%'")
            db.commit()
        migrated = SyncService(Config(self.path, TOKEN), clock=lambda: self.today)
        response = migrated.sync({'instance_id': self.instance, 'cursor': 0, 'operations': []})
        self.assertEqual(response['instance_id'], self.instance)
        self.assertEqual(response['changes'], [task])
        self.assertEqual(response['personal_sync'], 1)


if __name__ == '__main__':
    unittest.main()
