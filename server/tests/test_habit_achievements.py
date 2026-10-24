"""Habit-day scoring, plan history, legacy clients and transactional settlement."""
from contextlib import closing
import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import unittest
import uuid

from app import ApiError, Config, SyncService, backup_database, habit_month_achievement
from test_sync import TOKEN, operation


class HabitAchievementTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=os.environ.get('NAS_TODO_TEST_TMP'))
        self.path = Path(self.directory.name) / 'score.sqlite'
        self.day = dt.date(2026, 10, 1)
        self.service = SyncService(Config(self.path, TOKEN), clock=lambda: self.day)
        self.instance = self.base()['instance_id']

    def tearDown(self):
        self.directory.cleanup()

    def base(self, ops=()):
        return self.service.sync({'instance_id': getattr(self, 'instance', None), 'cursor': 0, 'operations': list(ops)})

    def personal(self, ops=()):
        return self.service.sync_personal({'instance_id': self.instance, 'cursor': 0, 'operations': list(ops)})

    def habit(self, *, habit_id=None, base=0, goal=8, weekdays=None, delete=False, history=None):
        op = {'op_id': str(uuid.uuid4()), 'kind': 'habit', 'id': habit_id or str(uuid.uuid4()),
              'base_version': base, 'action': 'delete' if delete else 'upsert',
              'data': {'name': '喝水', 'goal_type': 'count', 'goal': goal, 'weekdays': weekdays or list(range(1, 8))}}
        if history is not None:
            op['plan_history'] = history
        return op

    def check(self, habit_id, day, value):
        return {'op_id': str(uuid.uuid4()), 'kind': 'habit_checkin', 'id': habit_id + ':' + day,
                'base_version': 0, 'action': 'upsert', 'data': {'habit_id': habit_id, 'date': day, 'value': value}}

    def test_separate_thresholds_prevent_tasks_from_masking_habit_failures(self):
        tasks = [{'due_date': '2026-10-05', 'completed': True, 'deleted': False} for _ in range(20)]
        plan = {'habit_id': 'water', 'effective_from': '2026-10-05', 'goal': 8,
                'weekdays': [1, 2, 3, 4, 5], 'active': True}
        checks = [{'habit_id': 'water', 'date': f'2026-10-{d:02}', 'value': 8 if d < 8 else 7} for d in range(5, 10)]
        week = habit_month_achievement('2026-10', tasks, [plan], checks, through=dt.date(2026, 10, 9))['weeks'][1]
        self.assertEqual((week['task_total'], week['task_completed'], week['habit_total'], week['habit_completed']), (20, 20, 5, 3))
        self.assertFalse(week['star'])  # Combined 23/25 would incorrectly pass.
        checks[3]['value'] = 100
        self.assertTrue(habit_month_achievement('2026-10', tasks, [plan], checks, through=dt.date(2026, 10, 9))['weeks'][1]['star'])

    def test_habit_only_rest_days_future_days_and_partial_weeks(self):
        plan = {'habit_id': 'read', 'effective_from': '2026-10-01', 'goal': 1,
                'weekdays': [4, 5], 'active': True}
        report = habit_month_achievement('2026-10', [], [plan], [{'habit_id': 'read', 'date': '2026-10-01', 'value': 1}], through=dt.date(2026, 10, 1))
        self.assertEqual((report['total'], report['completed'], report['stars']), (1, 1, 1))
        self.assertEqual(report['weeks'][1]['total'], 0)
        self.assertEqual(habit_month_achievement('2026-10', [], [], [])['status'], 'empty')

    def test_plan_changes_and_deletion_preserve_earlier_days(self):
        create = self.habit(goal=8)
        self.personal([create, self.check(create['id'], '2026-10-01', 8)])
        self.day = dt.date(2026, 10, 2)
        edit = self.habit(habit_id=create['id'], base=1, goal=10)
        self.personal([edit, self.check(create['id'], '2026-10-02', 8)])
        self.day = dt.date(2026, 10, 3)
        self.personal([self.habit(habit_id=create['id'], base=2, goal=10, delete=True)])
        week = self.base()['achievement_v2']['live']['weeks'][0]
        self.assertEqual((week['habit_total'], week['habit_completed'], week['star']), (2, 1, False))
        self.assertEqual(self.base()['achievement']['live']['status'], 'empty')

    def test_offline_plan_history_is_atomic_durable_and_idempotent(self):
        self.day = dt.date(2026, 10, 4)
        create = self.habit()
        create['plan_history'] = [{'habit_id': create['id'], 'effective_from': '2026-10-02', 'goal': 8,
                                  'weekdays': list(range(1, 8)), 'active': True}]
        response = self.personal([create, self.check(create['id'], '2026-10-02', 8)])
        self.assertEqual((response['achievement_v2']['live']['total'], response['achievement_v2']['live']['completed']), (3, 1))
        retry = self.personal([create])
        self.assertEqual(retry['results'][0], response['results'][0])
        altered = json.loads(json.dumps(create)); altered['plan_history'][0]['effective_from'] = '2026-10-01'
        with self.assertRaises(ApiError) as error:
            self.personal([altered])
        self.assertEqual(error.exception.code, 'op_id_reused')
        self.service = SyncService(Config(self.path, TOKEN), clock=lambda: self.day)
        self.assertEqual(self.base()['achievement_v2']['live']['total'], 3)

    def test_settlement_keeps_habits_and_returns_legacy_projection(self):
        create = self.habit(goal=1, weekdays=[4])
        self.personal([create, self.check(create['id'], '2026-10-01', 1)])
        self.base([operation(due_date='2026-10-01', completed=True, list_name='工作')])
        self.day = dt.date(2026, 11, 1)
        response = self.base()
        v2 = response['achievement_v2']['settled'][0]
        self.assertEqual((v2['weeks'][0]['task_total'], v2['weeks'][0]['habit_total']), (1, 1))
        self.assertEqual(v2['weeks'][0]['star'], True)
        self.assertEqual(v2['cleaned'], 1)
        self.assertEqual(response['achievement']['settled'][0]['total'], 1)
        with closing(self.service.connect()) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM personal_records WHERE kind='habit' AND deleted=0").fetchone()[0], 1)
        backup = self.path.with_name('backup.sqlite'); backup_database(self.path, backup)
        with closing(__import__('sqlite3').connect(backup)) as db:
            self.assertEqual(json.loads(db.execute('SELECT report_json FROM achievement_months').fetchone()[0]), v2)
        # A late offline check-in cannot rewrite an already settled month.
        self.personal([self.check(create['id'], '2026-10-08', 1)])
        self.assertEqual(self.base()['achievement_v2']['settled'][0], v2)

    def test_upgrade_existing_habit_does_not_invent_past_obligations(self):
        create = self.habit(); self.personal([create])
        with closing(self.service.connect()) as db:
            db.execute('DROP TABLE habit_achievement_plans')
            db.execute("DELETE FROM metadata WHERE key='habit_achievement_start'")
        self.day = dt.date(2026, 10, 24)
        self.service = SyncService(Config(self.path, TOKEN), clock=lambda: self.day)
        score = self.base()['achievement_v2']
        self.assertEqual(score['habit_started_on'], '2026-10-24')
        self.assertEqual(score['live']['total'], 1)


if __name__ == '__main__':
    unittest.main()
