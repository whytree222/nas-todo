"""Monthly snapshot/cleanup checks using an isolated SQLite database and clock."""
import datetime as dt
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import Config, SyncService, month_achievement, backup_database
from test_sync import operation, TOKEN


class AchievementTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=os.environ.get('NAS_TODO_TEST_TMP'))
        self.path = Path(self.directory.name) / 'todo.sqlite'
        self.today = dt.date(2026, 10, 1)
        self.service = SyncService(Config(self.path, TOKEN), clock=lambda: self.today)
        self.instance_id = self.service.sync({'instance_id': None, 'cursor': 0, 'operations': []})['instance_id']

    def tearDown(self):
        self.directory.cleanup()

    def sync(self, operations=(), cursor=0):
        return self.service.sync({'instance_id': self.instance_id, 'cursor': cursor, 'operations': list(operations)})

    def test_eighty_percent_partial_weeks_and_empty_month(self):
        tasks = [{'due_date': '2026-10-01', 'completed': index < 4, 'deleted': False} for index in range(5)]
        tasks += [{'due_date': '2026-10-05', 'completed': index < 3, 'deleted': False} for index in range(5)]
        report = month_achievement('2026-10', tasks)
        self.assertEqual((report['weeks'][0]['start'], report['weeks'][0]['end']), ('2026-10-01', '2026-10-04'))
        self.assertTrue(report['weeks'][0]['star'])
        self.assertFalse(report['weeks'][1]['star'])
        self.assertEqual((report['stars'], report['status']), (1, 'red'))
        self.assertEqual(month_achievement('2024-02', [])['status'], 'empty')
        self.assertEqual(month_achievement('2024-02', [])['weeks'][-1]['end'], '2024-02-29')

    def test_atomic_settlement_archives_completed_and_unfinished_but_keeps_exclusions(self):
        batch = [operation(due_date='2026-10-01', list_name='工作', completed=index < 4) for index in range(5)]
        inbox = operation(due_date='2026-10-01', list_name='收件箱', completed=True)
        unclassified = operation(due_date='2026-10-02', list_name='未分类', completed=True)
        undated = operation(due_date=None, list_name='工作')
        future = operation(due_date='2026-11-01', list_name='工作')
        previous = operation(due_date='2026-09-01', list_name='工作')
        response = self.sync(batch + [inbox, unclassified, undated, future, previous])
        self.today = dt.date(2026, 11, 1)
        response = self.sync(cursor=response['cursor'])
        report = response['achievement']['settled'][0]
        self.assertEqual((report['cleaned'], report['total'], report['completed'], report['stars'], report['status']), (5, 7, 6, 1, 'green'))
        self.assertEqual(len(response['changes']), 5)
        self.assertTrue(all(t['deleted'] and t['version'] == 2 for t in response['changes']))
        with closing(self.service.connect()) as connection:
            self.assertEqual(connection.execute('SELECT count(*) FROM achievement_archive').fetchone()[0], 5)
            for task in (inbox, unclassified, undated, future, previous):
                self.assertEqual(connection.execute('SELECT deleted FROM tasks WHERE id=?', (task['task_id'],)).fetchone()[0], 0)
        again = self.sync(cursor=response['cursor'])
        self.assertEqual(again['changes'], [])
        self.assertEqual(again['achievement']['settled'], response['achievement']['settled'])

    def test_failed_transaction_rolls_back_snapshot_archive_and_deletion(self):
        self.sync([operation(list_name='工作')])
        self.today = dt.date(2026, 11, 1)
        connection = self.service.connect()
        connection.execute("CREATE TRIGGER fail_archive BEFORE INSERT ON achievement_archive BEGIN SELECT RAISE(ABORT, 'test disk failure'); END")
        connection.close()
        with self.assertRaises(sqlite3.IntegrityError):
            self.service.settle_months()
        connection = self.service.connect()
        self.assertEqual(connection.execute('SELECT count(*) FROM achievement_months').fetchone()[0], 0)
        self.assertEqual(connection.execute('SELECT deleted FROM tasks').fetchone()[0], 0)
        connection.execute('DROP TRIGGER fail_archive')
        connection.close()
        self.service.settle_months()
        self.assertEqual(len(self.sync()['achievement']['settled']), 1)

    def test_december_rollover_restart_backup_and_late_offline_tasks(self):
        self.today = dt.date(2026, 12, 15)
        december = operation(due_date='2026-12-21', list_name='生活', completed=True)
        self.sync([december])
        self.today = dt.date(2027, 1, 1)
        self.service.settle_months()
        self.service = SyncService(Config(self.path, TOKEN), clock=lambda: self.today)
        late = operation(due_date='2026-12-22', list_name='生活')
        response = self.sync([late])
        self.assertEqual(response['achievement']['live']['month'], '2027-01')
        december_report = response['achievement']['settled'][-1]
        self.assertEqual((december_report['month'], december_report['status'], december_report['total']), ('2026-12', 'green', 1))
        self.assertFalse(response['results'][0]['task']['deleted'])
        snapshot = self.path.with_name('backup.sqlite')
        backup_database(self.path, snapshot)
        connection = sqlite3.connect(snapshot)
        saved = json.loads(connection.execute("SELECT report_json FROM achievement_months WHERE month='2026-12'").fetchone()[0])
        self.assertEqual(saved, december_report)
        self.assertEqual(connection.execute("SELECT count(*) FROM achievement_archive WHERE month='2026-12'").fetchone()[0], 1)
        connection.close()

    def test_inbox_only_month_still_counts_for_score_but_is_not_cleaned(self):
        self.sync([operation(completed=False, list_name='收件箱')])
        self.today = dt.date(2026, 11, 1)
        self.service.settle_months()
        report = self.sync()['achievement']['settled'][0]
        self.assertEqual((report['status'], report['cleaned'], report['total']), ('red', 0, 1))


if __name__ == '__main__':
    unittest.main()
