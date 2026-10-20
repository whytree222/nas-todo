#!/usr/bin/env python3
"""Small private NAS todo sync service. Python 3.12+, standard library only."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import hmac
import json
import logging
import os
from pathlib import Path
import re
import socket
import sqlite3
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
import uuid


ACHIEVEMENT_TZ = dt.timezone(dt.timedelta(hours=8))
UNCATEGORIZED_LISTS = {"", "收件箱", "未分类"}


def following_month(day: dt.date) -> dt.date:
    return dt.date(day.year + (day.month == 12), day.month % 12 + 1, 1)


def month_achievement(month: str, tasks: list[dict[str, Any]], *, settled: bool = False) -> dict[str, Any]:
    first = dt.date.fromisoformat(month + "-01")
    last = following_month(first) - dt.timedelta(days=1)
    weeks = []
    start = first
    while start <= last:
        end = min(start + dt.timedelta(days=6 - start.weekday()), last)
        entries = [task for task in tasks if not task["deleted"] and task["due_date"] is not None
                   and start.isoformat() <= task["due_date"] <= end.isoformat()]
        total = len(entries)
        completed = sum(task["completed"] for task in entries)
        weeks.append({"start": start.isoformat(), "end": end.isoformat(), "total": total,
                      "completed": completed, "star": total > 0 and completed * 5 >= total * 4})
        start = end + dt.timedelta(days=1)
    active = [week for week in weeks if week["total"] > 0]
    return {"month": month, "weeks": weeks, "total": sum(w["total"] for w in weeks),
            "completed": sum(w["completed"] for w in weeks), "stars": sum(w["star"] for w in weeks),
            "status": "empty" if not active else "green" if all(w["star"] for w in active) else "red",
            "settled": settled, "cleaned": 0}


MAX_BODY_BYTES = 1024 * 1024
MAX_OPERATIONS = 100
MAX_SQLITE_INT = (1 << 63) - 1
DATA_KEYS = {"title", "note", "list_name", "due_date", "priority", "completed"}
OPERATION_KEYS = {"op_id", "task_id", "base_version", "action", "data"}
REQUEST_KEYS = {"instance_id", "cursor", "operations"}


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


@dataclass(frozen=True)
class Config:
    db_path: Path
    token: str
    host: str = "0.0.0.0"
    port: int = 8787
    max_tasks: int = 10_000
    max_workers: int = 32
    max_data_bytes: int = 16 * 1024 * 1024

    def validate(self) -> None:
        if len(self.token) < 32 or any(not 33 <= ord(char) <= 126 for char in self.token):
            raise ValueError("NAS_TODO_TOKEN must contain at least 32 printable ASCII characters without spaces")
        if not 0 <= self.port <= 65535:
            raise ValueError("Port must be between 0 and 65535")
        if not 1 <= self.max_tasks <= 10_000 or not 1 <= self.max_workers <= 128:
            raise ValueError("Invalid service capacity")
        if not 1 <= self.max_data_bytes <= 16 * 1024 * 1024:
            raise ValueError("Invalid data capacity")


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def encode_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True, allow_nan=False)


def require_keys(value: Any, keys: set[str], name: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ApiError(400, "invalid_request", f"{name} must contain exactly: {', '.join(sorted(keys))}")
    return value


def require_integer(value: Any, name: str) -> int:
    if type(value) is not int or not 0 <= value <= MAX_SQLITE_INT:
        raise ApiError(400, "invalid_request", f"{name} must be a nonnegative integer")
    return value


def require_uuid(value: Any, name: str) -> str:
    if not isinstance(value, str) or len(value) != 36:
        raise ApiError(400, "invalid_request", f"{name} must be a hyphenated UUID")
    try:
        parsed = str(uuid.UUID(value))
    except ValueError:
        raise ApiError(400, "invalid_request", f"{name} must be a hyphenated UUID") from None
    if parsed != value.lower():
        raise ApiError(400, "invalid_request", f"{name} must be a hyphenated UUID")
    return parsed


def require_text(value: Any, name: str, maximum: int, *, nonempty: bool = False) -> str:
    if not isinstance(value, str) or len(value) > maximum or (nonempty and not value.strip()):
        raise ApiError(400, "invalid_request", f"{name} is invalid (maximum {maximum} characters)")
    # JSON permits escaped unpaired surrogates, which cannot be stored as UTF-8.
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        raise ApiError(400, "invalid_request", f"{name} must contain valid Unicode") from None
    return value


def validate_request(value: Any) -> dict[str, Any]:
    deferred = False
    if isinstance(value, dict) and set(value) == REQUEST_KEYS | {'defer_repeats'}:
        if type(value['defer_repeats']) is not bool:
            raise ApiError(400, 'invalid_request', 'defer_repeats must be a boolean')
        deferred = value['defer_repeats']
        value = {key: value[key] for key in REQUEST_KEYS}
    request = require_keys(value, REQUEST_KEYS, "request")
    instance_id = request["instance_id"]
    if instance_id is not None:
        instance_id = require_uuid(instance_id, "instance_id")
    cursor = require_integer(request["cursor"], "cursor")
    operations = request["operations"]
    if not isinstance(operations, list) or len(operations) > MAX_OPERATIONS:
        raise ApiError(400, "invalid_request", f"operations must be a list of at most {MAX_OPERATIONS} items")
    seen: set[str] = set()
    validated = []
    for item in operations:
        operation = require_keys(item, OPERATION_KEYS, "operation")
        op_id = require_uuid(operation["op_id"], "op_id")
        if op_id in seen:
            raise ApiError(400, "duplicate_operation", "An op_id may occur only once per request")
        seen.add(op_id)
        task_id = require_uuid(operation["task_id"], "task_id")
        base_version = require_integer(operation["base_version"], "base_version")
        action = operation["action"]
        if action not in ("upsert", "delete"):
            raise ApiError(400, "invalid_request", "action must be upsert or delete")
        data = require_keys(operation["data"], DATA_KEYS, "data")
        title = require_text(data["title"], "title", 200, nonempty=True)
        note = require_text(data["note"], "note", 10_000)
        list_name = require_text(data["list_name"], "list_name", 60)
        due_date = data["due_date"]
        if due_date is not None:
            if not isinstance(due_date, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", due_date):
                raise ApiError(400, "invalid_request", "due_date must be null or YYYY-MM-DD")
            try:
                dt.date.fromisoformat(due_date)
            except ValueError:
                raise ApiError(400, "invalid_request", "due_date must be a real calendar date") from None
        if type(data["priority"]) is not int or data["priority"] not in (0, 1, 2):
            raise ApiError(400, "invalid_request", "priority must be 0, 1, or 2")
        if type(data["completed"]) is not bool:
            raise ApiError(400, "invalid_request", "completed must be a boolean")
        validated.append({
            "op_id": op_id, "task_id": task_id, "base_version": base_version, "action": action,
            "data": {"title": title, "note": note, "list_name": list_name, "due_date": due_date,
                     "priority": data["priority"], "completed": data["completed"]},
        })
    return {"instance_id": instance_id, "cursor": cursor, "operations": validated, 'defer_repeats': deferred}


def row_to_task(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    result = dict(row)
    result["completed"] = bool(result["completed"])
    result["deleted"] = bool(result["deleted"])
    return result


class PersonalFeatures:
    """Versioned sidecar collections keep the original six-field API compatible."""

    def _initialize_personal(self, connection):
        connection.execute('CREATE TABLE IF NOT EXISTS deferred_repeats (task_id TEXT PRIMARY KEY)')
        connection.execute("CREATE TABLE IF NOT EXISTS personal_records (kind TEXT NOT NULL,id TEXT NOT NULL,data_json TEXT NOT NULL,deleted INTEGER NOT NULL,version INTEGER NOT NULL,updated_at TEXT NOT NULL,change_seq INTEGER NOT NULL UNIQUE,PRIMARY KEY(kind,id))")
        connection.execute("CREATE TABLE IF NOT EXISTS personal_operations (op_id TEXT PRIMARY KEY,payload_hash TEXT NOT NULL,result_json TEXT NOT NULL)")
        connection.execute("CREATE TABLE IF NOT EXISTS repeat_spawns (source_id TEXT PRIMARY KEY,next_id TEXT NOT NULL UNIQUE)")
        connection.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('personal_cursor','0')")
        used = connection.execute('SELECT coalesce(sum(length(cast(data_json AS BLOB))),0) FROM personal_records').fetchone()[0]
        connection.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('personal_data_bytes',?)", (str(used),))

    def _personal_row(self, row):
        if row is None:
            return None
        return {"kind": row["kind"], "id": row["id"], "data": json.loads(row["data_json"]),
                "deleted": bool(row["deleted"]), "version": row["version"],
                "updated_at": row["updated_at"], "change_seq": row["change_seq"]}

    def _put_personal(self, connection, kind, record_id, data, *, deleted=False):
        old = connection.execute("SELECT * FROM personal_records WHERE kind=? AND id=?", (kind, record_id)).fetchone()
        encoded = encode_json(data)
        size = int(connection.execute("SELECT value FROM metadata WHERE key='personal_data_bytes'").fetchone()[0]) + len(encoded.encode('utf-8')) - (len(old['data_json'].encode('utf-8')) if old else 0)
        if size > self.config.max_data_bytes or (old is None and connection.execute('SELECT count(*) FROM personal_records').fetchone()[0] >= 50000):
            raise ApiError(409, 'capacity_exceeded', 'Personal data capacity reached; existing data is preserved')
        cursor = int(connection.execute("SELECT value FROM metadata WHERE key='personal_cursor'").fetchone()[0]) + 1
        connection.execute("INSERT INTO personal_records VALUES(?,?,?,?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET data_json=excluded.data_json,deleted=excluded.deleted,version=excluded.version,updated_at=excluded.updated_at,change_seq=excluded.change_seq",
                           (kind, record_id, encoded, int(deleted), old["version"] + 1 if old else 1, utc_now(), cursor))
        connection.execute("UPDATE metadata SET value=? WHERE key='personal_data_bytes'", (str(size),))
        connection.execute("UPDATE metadata SET value=? WHERE key='personal_cursor'", (str(cursor),))
        return self._personal_row(connection.execute("SELECT * FROM personal_records WHERE kind=? AND id=?", (kind, record_id)).fetchone())

    def _personal_data(self, kind, value):
        if kind == 'habit':
            data = require_keys(value, {'name', 'goal_type', 'goal', 'weekdays'}, 'habit')
            name = require_text(data['name'], 'name', 80, nonempty=True).strip()
            if data['goal_type'] not in ('bool', 'count'):
                raise ApiError(400, 'invalid_request', 'Invalid habit goal type')
            goal = require_integer(data['goal'], 'goal')
            if not 1 <= goal <= 100000 or (data['goal_type'] == 'bool' and goal != 1):
                raise ApiError(400, 'invalid_request', 'Invalid habit goal')
            return {'name': name, 'goal_type': data['goal_type'], 'goal': goal,
                    'weekdays': self._weekdays(data['weekdays'], nonempty=True)}
        if kind == 'habit_checkin':
            data = require_keys(value, {'habit_id', 'date', 'value'}, 'checkin')
            habit_id = require_uuid(data['habit_id'], 'habit_id')
            day = self._personal_date(data['date'])
            amount = require_integer(data['value'], 'value')
            if amount > 100000:
                raise ApiError(400, 'invalid_request', 'Check-in value too large')
            return {'habit_id': habit_id, 'date': day, 'value': amount}
        if kind != 'task_meta':
            raise ApiError(400, 'invalid_request', 'Unknown personal collection')
        data = require_keys(value, {'parent_id', 'tags', 'repeat_rule'}, 'task metadata')
        parent = None if data['parent_id'] is None else require_uuid(data['parent_id'], 'parent_id')
        if not isinstance(data['tags'], list) or len(data['tags']) > 20:
            raise ApiError(400, 'invalid_request', 'At most 20 tags are allowed')
        tags = sorted(set(require_text(tag, 'tag', 30, nonempty=True).strip() for tag in data['tags']))
        repeat = data['repeat_rule']
        if repeat is not None:
            repeat = require_keys(repeat, {'frequency', 'interval', 'weekdays', 'month_day'}, 'repeat rule')
            interval = require_integer(repeat['interval'], 'interval')
            if repeat['frequency'] not in ('daily', 'weekly', 'monthly') or not 1 <= interval <= 365:
                raise ApiError(400, 'invalid_request', 'Invalid repeat frequency or interval')
            month_day = repeat['month_day']
            if month_day is not None and (type(month_day) is not int or not 1 <= month_day <= 31):
                raise ApiError(400, 'invalid_request', 'Invalid repeat month day')
            repeat = {'frequency': repeat['frequency'], 'interval': interval,
                      'weekdays': self._weekdays(repeat['weekdays']), 'month_day': month_day}
        return {'parent_id': parent, 'tags': tags, 'repeat_rule': repeat}

    def _personal_date(self, value):
        if not isinstance(value, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
            raise ApiError(400, 'invalid_request', 'Invalid calendar date')
        try:
            dt.date.fromisoformat(value)
        except ValueError:
            raise ApiError(400, 'invalid_request', 'Invalid calendar date') from None
        return value

    def _weekdays(self, value, *, nonempty=False):
        if not isinstance(value, list) or len(value) > 7 or any(type(v) is not int or not 1 <= v <= 7 for v in value) or (nonempty and not value):
            raise ApiError(400, 'invalid_request', 'Invalid weekdays')
        return sorted(set(value))

    def _valid_personal_reference(self, connection, kind, record_id, data):
        if kind == 'habit':
            return True
        if kind == 'habit_checkin':
            habit = connection.execute("SELECT * FROM personal_records WHERE kind='habit' AND id=? AND deleted=0", (data['habit_id'],)).fetchone()
            return habit is not None and record_id == data['habit_id'] + ':' + data['date'] and (json.loads(habit['data_json'])['goal_type'] != 'bool' or data['value'] <= 1)
        task = connection.execute('SELECT * FROM tasks WHERE id=? AND deleted=0', (record_id,)).fetchone()
        if task is None or (data['repeat_rule'] is not None and task['due_date'] is None):
            return False
        parent = data['parent_id']
        seen = {record_id}
        depth = 1
        while parent is not None:
            if parent in seen or depth >= 5:
                return False
            seen.add(parent)
            if connection.execute('SELECT 1 FROM tasks WHERE id=? AND deleted=0', (parent,)).fetchone() is None:
                # A parent deleted concurrently must not discard its child.
                data['parent_id'] = None
                return True
            row = connection.execute("SELECT data_json FROM personal_records WHERE kind='task_meta' AND id=? AND deleted=0", (parent,)).fetchone()
            parent = json.loads(row[0])['parent_id'] if row else None
            depth += 1
        # Reparenting an existing branch must also respect descendant depth.
        parents = {row['id']: json.loads(row['data_json'])['parent_id'] for row in connection.execute("SELECT * FROM personal_records WHERE kind='task_meta' AND deleted=0")}
        parents[record_id] = data['parent_id']
        for child in parents:
            current, chain = child, set()
            while current is not None:
                if current in chain or len(chain) >= 5:
                    return False
                chain.add(current)
                current = parents.get(current)
        return True

    def _promote_orphans(self, connection):
        for row in connection.execute("SELECT * FROM personal_records WHERE kind='task_meta' AND deleted=0").fetchall():
            data = json.loads(row['data_json'])
            parent = data['parent_id']
            if parent is not None and connection.execute('SELECT 1 FROM tasks WHERE id=? AND deleted=0', (parent,)).fetchone() is None:
                data['parent_id'] = None
                self._put_personal(connection, 'task_meta', row['id'], data)

    @staticmethod
    def _next_repeat_date(day, rule):
        if rule['frequency'] == 'daily':
            return day + dt.timedelta(days=rule['interval'])
        if rule['frequency'] == 'weekly':
            weekdays = rule['weekdays'] or [day.isoweekday()]
            for weekday in weekdays:
                if weekday > day.isoweekday():
                    return day + dt.timedelta(days=weekday - day.isoweekday())
            return day + dt.timedelta(days=rule['interval'] * 7 - day.weekday() + weekdays[0] - 1)
        index = day.year * 12 + day.month - 1 + rule['interval']
        year, month = divmod(index, 12)
        month += 1
        first = dt.date(year, month, 1)
        last = following_month(first) - dt.timedelta(days=1)
        return dt.date(year, month, min(rule['month_day'] or day.day, last.day))

    def _generate_repeats(self, connection):
        generated = []
        for row in connection.execute("SELECT t.*,p.data_json FROM tasks t JOIN personal_records p ON p.kind='task_meta' AND p.id=t.id AND p.deleted=0 LEFT JOIN repeat_spawns r ON r.source_id=t.id LEFT JOIN deferred_repeats d ON d.task_id=t.id WHERE t.deleted=0 AND t.completed=1 AND t.due_date IS NOT NULL AND r.source_id IS NULL AND d.task_id IS NULL").fetchall():
            meta = json.loads(row['data_json'])
            rule = meta['repeat_rule']
            if rule is None:
                continue
            try:
                next_day = self._next_repeat_date(dt.date.fromisoformat(row['due_date']), rule)
            except (ValueError, OverflowError):
                continue
            if connection.execute('SELECT count(*) FROM tasks').fetchone()[0] >= self.config.max_tasks:
                raise ApiError(409, 'capacity_exceeded', 'No capacity for the next repeated task')
            next_id = str(uuid.uuid5(uuid.NAMESPACE_URL, 'nas-todo:repeat:' + row['id'] + ':' + row['due_date']))
            data = {key: row[key] for key in DATA_KEYS}
            data.update(completed=False, due_date=next_day.isoformat())
            size = int(connection.execute("SELECT value FROM metadata WHERE key='data_bytes'").fetchone()[0]) + len(encode_json(data).encode('utf-8'))
            if size > self.config.max_data_bytes:
                raise ApiError(409, 'capacity_exceeded', 'No data capacity for the next repeated task')
            cursor = int(connection.execute("SELECT value FROM metadata WHERE key='cursor'").fetchone()[0]) + 1
            connection.execute('INSERT INTO tasks VALUES(?,?,?,?,?,?,0,0,1,?,?)', (next_id, row['title'], row['note'], row['list_name'], next_day.isoformat(), row['priority'], utc_now(), cursor))
            connection.execute("UPDATE metadata SET value=? WHERE key='cursor'", (str(cursor),))
            connection.execute("UPDATE metadata SET value=? WHERE key='data_bytes'", (str(size),))
            connection.execute('INSERT INTO repeat_spawns VALUES(?,?)', (row['id'], next_id))
            if rule['frequency'] == 'monthly' and rule['month_day'] is None:
                meta = {**meta, 'repeat_rule': {**rule, 'month_day': dt.date.fromisoformat(row['due_date']).day}}
            self._put_personal(connection, 'task_meta', next_id, meta)
            generated.append(row_to_task(connection.execute('SELECT * FROM tasks WHERE id=?', (next_id,)).fetchone()))
        return generated

    def sync_personal(self, value):
        release_tasks = []
        if isinstance(value, dict) and set(value) == REQUEST_KEYS | {'release_tasks'}:
            if not isinstance(value['release_tasks'], list) or len(value['release_tasks']) > 100:
                raise ApiError(400, 'invalid_request', 'At most 100 repeat releases are allowed')
            release_tasks = list(dict.fromkeys(require_uuid(item, 'release task') for item in value['release_tasks']))
            value = {key: value[key] for key in REQUEST_KEYS}
        request = require_keys(value, REQUEST_KEYS, 'personal request')
        cursor = require_integer(request['cursor'], 'cursor')
        instance = request['instance_id']
        if instance is not None:
            instance = require_uuid(instance, 'instance_id')
        raw_ops = request['operations']
        if not isinstance(raw_ops, list) or len(raw_ops) > MAX_OPERATIONS:
            raise ApiError(400, 'invalid_request', 'At most 100 personal operations are allowed')
        ops, seen = [], set()
        for raw in raw_ops:
            op = require_keys(raw, {'op_id', 'kind', 'id', 'base_version', 'action', 'data'}, 'personal operation')
            op_id = require_uuid(op['op_id'], 'op_id')
            if op_id in seen:
                raise ApiError(400, 'duplicate_operation', 'Duplicate operation')
            seen.add(op_id)
            kind = op['kind']
            if kind not in ('task_meta', 'habit', 'habit_checkin'):
                raise ApiError(400, 'invalid_request', 'Unknown collection')
            record_id = require_text(op['id'], 'id', 100, nonempty=True)
            if kind != 'habit_checkin':
                record_id = require_uuid(record_id, 'id')
            base = require_integer(op['base_version'], 'base_version')
            if op['action'] not in ('upsert', 'delete') or (kind == 'task_meta' and op['action'] == 'delete'):
                raise ApiError(400, 'invalid_request', 'Invalid personal action')
            data = self._personal_data(kind, op['data'])
            ops.append({'op_id': op_id, 'kind': kind, 'id': record_id, 'base_version': base, 'action': op['action'], 'data': data})
        connection = self.connect()
        try:
            connection.execute('BEGIN IMMEDIATE')
            metadata = dict(connection.execute('SELECT key,value FROM metadata'))
            if instance != metadata['instance_id']:
                raise ApiError(409, 'instance_mismatch', 'Personal sync must bind to the same NAS database')
            if cursor > int(metadata['personal_cursor']):
                raise ApiError(409, 'future_cursor', 'Personal cursor ahead of database')
            # Validate every reused op id before applying any write in this batch.
            history, hashes = {}, {}
            for op in ops:
                digest = hashlib.sha256(encode_json(op).encode('utf-8')).hexdigest()
                previous = connection.execute('SELECT * FROM personal_operations WHERE op_id=?', (op['op_id'],)).fetchone()
                if previous is not None and previous['payload_hash'] != digest:
                    raise ApiError(409, 'op_id_reused', 'Personal operation id reused with another payload')
                history[op['op_id']], hashes[op['op_id']] = previous, digest
            results = []
            for op in ops:
                previous = history[op['op_id']]
                if previous is not None:
                    results.append(json.loads(previous['result_json']))
                    continue
                old = connection.execute('SELECT * FROM personal_records WHERE kind=? AND id=?', (op['kind'], op['id'])).fetchone()
                match = (old is None and op['base_version'] == 0 and op['action'] == 'upsert') or (old is not None and not old['deleted'] and old['version'] == op['base_version'])
                valid = op['action'] == 'delete' or self._valid_personal_reference(connection, op['kind'], op['id'], op['data'])
                equivalent = old is not None and not old['deleted'] and op['action'] == 'upsert' and encode_json(op['data']) == old['data_json']
                if equivalent and valid:
                    result = {'op_id': op['op_id'], 'status': 'applied', 'record': self._personal_row(old)}
                elif not match or not valid:
                    result = {'op_id': op['op_id'], 'status': 'conflict', 'record': self._personal_row(old)}
                else:
                    data = json.loads(old['data_json']) if op['action'] == 'delete' else op['data']
                    record = self._put_personal(connection, op['kind'], op['id'], data, deleted=op['action'] == 'delete')
                    result = {'op_id': op['op_id'], 'status': 'applied', 'record': record}
                connection.execute('INSERT INTO personal_operations VALUES(?,?,?)', (op['op_id'], hashes[op['op_id']], encode_json(result)))
                results.append(result)
            blocked = {op['id'] for op, result in zip(ops, results) if op['kind'] == 'task_meta' and result['status'] == 'conflict'}
            released = [record_id for record_id in release_tasks if record_id not in blocked]
            for record_id in released:
                connection.execute('DELETE FROM deferred_repeats WHERE task_id=?', (record_id,))
            self._promote_orphans(connection)
            generated = self._generate_repeats(connection)
            changes = [self._personal_row(row) for row in connection.execute('SELECT * FROM personal_records WHERE change_seq>? ORDER BY change_seq', (cursor,))]
            latest = int(connection.execute("SELECT value FROM metadata WHERE key='personal_cursor'").fetchone()[0])
            connection.commit()
            return {'instance_id': instance, 'cursor': latest, 'changes': changes, 'results': results, 'generated_tasks': generated, 'released_tasks': released}
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()


class SyncService(PersonalFeatures):
    def __init__(self, config: Config, *, clock=None) -> None:
        config.validate()
        self.config = config
        self.clock = clock or (lambda: dt.datetime.now(ACHIEVEMENT_TZ).date())
        config.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.initialize()

    def connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.config.db_path, timeout=10, isolation_level=None)
        try:
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA busy_timeout=10000")
            connection.execute("PRAGMA foreign_keys=ON")
            connection.execute("PRAGMA synchronous=FULL")
            return connection
        except BaseException:
            connection.close()
            raise

    def initialize(self) -> None:
        connection = self.connect()
        try:
            connection.execute("PRAGMA journal_mode=WAL")
            if connection.execute("PRAGMA user_version").fetchone()[0] not in (0, 1):
                raise ValueError("Unsupported database schema; refusing to open it")
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            connection.execute("""CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY, title TEXT NOT NULL, note TEXT NOT NULL, list_name TEXT NOT NULL,
                due_date TEXT, priority INTEGER NOT NULL CHECK(priority IN (0,1,2)),
                completed INTEGER NOT NULL CHECK(completed IN (0,1)),
                deleted INTEGER NOT NULL CHECK(deleted IN (0,1)),
                version INTEGER NOT NULL CHECK(version > 0), updated_at TEXT NOT NULL,
                change_seq INTEGER NOT NULL UNIQUE CHECK(change_seq > 0)
            )""")
            connection.execute("""CREATE TABLE IF NOT EXISTS operations (
                op_id TEXT PRIMARY KEY, payload_hash TEXT NOT NULL, result_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            )""")
            connection.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('instance_id',?)", (str(uuid.uuid4()),))
            connection.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('cursor','0')")
            connection.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('data_bytes','0')")
            connection.execute("CREATE TABLE IF NOT EXISTS achievement_months (month TEXT PRIMARY KEY, report_json TEXT NOT NULL)")
            connection.execute("""CREATE TABLE IF NOT EXISTS achievement_archive (
                month TEXT NOT NULL, task_id TEXT NOT NULL, task_json TEXT NOT NULL,
                PRIMARY KEY(month, task_id))""")
            # Start with the activation month; never clean older pre-feature data.
            month = self.clock().strftime('%Y-%m')
            connection.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('achievement_start_month',?)", (month,))
            connection.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('achievement_next_month',?)", (month,))
            self._initialize_personal(connection)
            connection.execute("PRAGMA user_version=1")
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _settle_locked(self, connection: sqlite3.Connection, today: dt.date) -> None:
        next_month = connection.execute("SELECT value FROM metadata WHERE key='achievement_next_month'").fetchone()[0]
        current = today.strftime('%Y-%m')
        cursor = int(connection.execute("SELECT value FROM metadata WHERE key='cursor'").fetchone()[0])
        while next_month < current:
            first = dt.date.fromisoformat(next_month + '-01')
            after = following_month(first)
            rows = connection.execute("SELECT * FROM tasks WHERE deleted=0 AND due_date>=? AND due_date<?",
                                      (first.isoformat(), after.isoformat())).fetchall()
            tasks = [row_to_task(row) for row in rows]
            report = month_achievement(next_month, tasks, settled=True)
            cleaned = [task for task in tasks if task['list_name'].strip() not in UNCATEGORIZED_LISTS]
            report['cleaned'] = len(cleaned)
            connection.execute("INSERT INTO achievement_months(month,report_json) VALUES(?,?)",
                               (next_month, encode_json(report)))
            for task in cleaned:
                # Archive first, then emit ordinary versioned tombstones to both clients.
                personal = connection.execute("SELECT data_json FROM personal_records WHERE kind='task_meta' AND id=? AND deleted=0", (task['id'],)).fetchone()
                if personal is not None:
                    task['personal_metadata'] = json.loads(personal[0])
                connection.execute("INSERT INTO achievement_archive(month,task_id,task_json) VALUES(?,?,?)",
                                   (next_month, task['id'], encode_json(task)))
                cursor += 1
                connection.execute("UPDATE tasks SET deleted=1,version=version+1,updated_at=?,change_seq=? WHERE id=?",
                                   (utc_now(), cursor, task['id']))
            next_month = after.strftime('%Y-%m')
            connection.execute("UPDATE metadata SET value=? WHERE key='achievement_next_month'", (next_month,))
        connection.execute("UPDATE metadata SET value=? WHERE key='cursor'", (str(cursor),))

    def settle_months(self) -> None:
        connection = self.connect()
        try:
            connection.execute('BEGIN IMMEDIATE')
            self._settle_locked(connection, self.clock())
            self._promote_orphans(connection)
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _achievement_state(self, connection: sqlite3.Connection) -> dict[str, Any]:
        today = self.clock()
        month = today.strftime('%Y-%m')
        tasks = [row_to_task(row) for row in connection.execute(
            'SELECT * FROM tasks WHERE deleted=0 AND due_date>=? AND due_date<?',
            (month + '-01', following_month(today).isoformat()))]
        return {'version': 1, 'today': today.isoformat(), 'start_month': connection.execute(
            "SELECT value FROM metadata WHERE key='achievement_start_month'").fetchone()[0],
            'live': month_achievement(month, tasks), 'settled': [json.loads(row[0]) for row in connection.execute(
                'SELECT report_json FROM achievement_months ORDER BY month')]}

    def sync(self, value: Any) -> dict[str, Any]:
        request = validate_request(value)
        operations = request["operations"]
        connection = self.connect()
        try:
            # One writer at a time. Versions, result history, and cursor commit together.
            connection.execute("BEGIN IMMEDIATE")
            self._settle_locked(connection, self.clock())
            metadata = dict(connection.execute("SELECT key,value FROM metadata"))
            instance_id = metadata["instance_id"]
            cursor = int(metadata["cursor"])
            data_bytes = int(metadata["data_bytes"])
            if request["instance_id"] is not None and request["instance_id"] != instance_id:
                raise ApiError(409, "instance_mismatch", "Server database identity changed; reconcile before syncing")
            if request["instance_id"] is None and request["cursor"] != 0:
                raise ApiError(409, "instance_required", "A nonzero cursor requires the server instance_id")
            if request["cursor"] > cursor:
                raise ApiError(409, "future_cursor", "Client cursor is ahead of this database; request a full snapshot before syncing")

            # Reject payload reuse before executing ANY operation in this batch.
            history: dict[str, sqlite3.Row | None] = {}
            hashes: dict[str, str] = {}
            for operation in operations:
                op_id = operation["op_id"]
                hashes[op_id] = hashlib.sha256(encode_json(operation).encode("utf-8")).hexdigest()
                previous = connection.execute("SELECT * FROM operations WHERE op_id=?", (op_id,)).fetchone()
                if previous is not None and previous["payload_hash"] != hashes[op_id]:
                    raise ApiError(409, "op_id_reused", "An op_id was reused with a different payload")
                history[op_id] = previous

            possible_new_ids = {
                operation["task_id"] for operation in operations
                if history[operation["op_id"]] is None
                and operation["action"] == "upsert" and operation["base_version"] == 0
                and connection.execute("SELECT 1 FROM tasks WHERE id=?", (operation["task_id"],)).fetchone() is None
            }
            task_count = connection.execute("SELECT count(*) FROM tasks").fetchone()[0]
            if task_count + len(possible_new_ids) > self.config.max_tasks:
                raise ApiError(409, "capacity_exceeded", "Server task capacity reached (including deletion history)")

            results = []
            for operation in operations:
                op_id, task_id = operation["op_id"], operation["task_id"]
                if history[op_id] is not None:
                    results.append(json.loads(history[op_id]["result_json"]))
                    continue
                row = connection.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone()
                matches = ((row is None and operation["action"] == "upsert" and operation["base_version"] == 0)
                           or (row is not None and not row["deleted"] and operation["base_version"] == row["version"]))
                if not matches:
                    result = {"op_id": op_id, "status": "conflict", "task": row_to_task(row)}
                else:
                    cursor += 1
                    updated_at = utc_now()
                    version = row["version"] + 1 if row else 1
                    if operation["action"] == "delete":
                        # Keep prior data in the tombstone. The deletion request cannot overwrite it.
                        connection.execute("UPDATE tasks SET deleted=1,version=?,updated_at=?,change_seq=? WHERE id=?",
                                           (version, updated_at, cursor, task_id))
                    else:
                        data = operation["data"]
                        old_task = row_to_task(row)
                        old_data = {key: old_task[key] for key in DATA_KEYS} if old_task else None
                        data_bytes += len(encode_json(data).encode("utf-8"))
                        if old_data is not None:
                            data_bytes -= len(encode_json(old_data).encode("utf-8"))
                        if data_bytes > self.config.max_data_bytes:
                            raise ApiError(409, "capacity_exceeded", "Server task data exceeds the 16 MiB capacity")
                        connection.execute("""INSERT INTO tasks
                            (id,title,note,list_name,due_date,priority,completed,deleted,version,updated_at,change_seq)
                            VALUES (?,?,?,?,?,?,?,0,?,?,?)
                            ON CONFLICT(id) DO UPDATE SET title=excluded.title,note=excluded.note,
                            list_name=excluded.list_name,due_date=excluded.due_date,priority=excluded.priority,
                            completed=excluded.completed,deleted=0,version=excluded.version,
                            updated_at=excluded.updated_at,change_seq=excluded.change_seq""",
                            (task_id, data["title"], data["note"], data["list_name"], data["due_date"],
                             data["priority"], int(data["completed"]), version, updated_at, cursor))
                    result = {"op_id": op_id, "status": "applied",
                              "task": row_to_task(connection.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone())}
                    if request['defer_repeats'] and operation['action'] == 'upsert':
                        connection.execute('INSERT OR IGNORE INTO deferred_repeats VALUES(?)', (task_id,))
                connection.execute("INSERT INTO operations(op_id,payload_hash,result_json,created_at) VALUES(?,?,?,?)",
                                   (op_id, hashes[op_id], encode_json(result), utc_now()))
                results.append(result)
            connection.execute("UPDATE metadata SET value=? WHERE key='cursor'", (str(cursor),))
            connection.execute("UPDATE metadata SET value=? WHERE key='data_bytes'", (str(data_bytes),))
            self._promote_orphans(connection)
            self._generate_repeats(connection)
            cursor = int(connection.execute("SELECT value FROM metadata WHERE key='cursor'").fetchone()[0])
            changes = [row_to_task(row) for row in connection.execute(
                "SELECT * FROM tasks WHERE change_seq>? ORDER BY change_seq", (request["cursor"],))]
            response = {"instance_id": instance_id, "cursor": cursor, "changes": changes, "results": results}
            response['personal_sync'] = 1
            response['achievement'] = self._achievement_state(connection)
            connection.commit()
            return response
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON object key")
        result[key] = value
    return result


class SyncHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "NAS-Todo"
    sys_version = ""

    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(20)

    def log_message(self, fmt: str, *args: Any) -> None:
        # Do not log URLs, Authorization, task contents, or response payloads.
        pass

    def send_json(self, status: int, value: Any, *, head_only: bool = False) -> None:
        body = encode_json(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        if not head_only:
            self.wfile.write(body)
        self.wfile.flush()
        logging.info("%s %s", self.command, status)

    def send_api_error(self, error: ApiError) -> None:
        self.send_json(error.status, {"error": error.code, "message": error.message})

    def discard_rejected_body(self) -> None:
        """Avoid a TCP reset discarding an early HTTP error during an upload.

        Authentication still happens before parsing or applying the request. Only
        discard a correctly framed, bounded body; do not wait for oversized,
        ambiguous, chunked, or Expect: 100-continue uploads. Send the response
        first, then allow up to two seconds total for an already-running upload.
        """
        if self.headers.get("Transfer-Encoding") is not None:
            return
        if self.headers.get("Expect", "").lower() == "100-continue":
            return
        lengths = self.headers.get_all("Content-Length", [])
        if len(lengths) != 1 or not re.fullmatch(r"[0-9]{1,10}", lengths[0]):
            return
        remaining = int(lengths[0])
        if remaining > MAX_BODY_BYTES:
            return
        original_timeout = self.connection.gettimeout()
        deadline = time.monotonic() + 2
        try:
            while remaining:
                timeout = deadline - time.monotonic()
                if timeout <= 0:
                    break
                self.connection.settimeout(timeout)
                chunk = self.rfile.read1(min(remaining, 64 * 1024))
                if not chunk:
                    break
                remaining -= len(chunk)
        except (OSError, ValueError):
            # Rejected requests never reach the database, even if the peer stops.
            pass
        finally:
            self.connection.settimeout(original_timeout)

    def authorize_and_length(self) -> int:
        if self.headers.get_all("Authorization") and len(self.headers.get_all("Authorization")) != 1:
            raise ApiError(401, "unauthorized", "A valid bearer token is required")
        expected = "Bearer " + self.server.service.config.token  # type: ignore[attr-defined]
        supplied = self.headers.get("Authorization", "")
        if not hmac.compare_digest(supplied.encode("utf-8"), expected.encode("utf-8")):
            raise ApiError(401, "unauthorized", "A valid bearer token is required")
        if self.headers.get("Transfer-Encoding") is not None:
            raise ApiError(400, "invalid_request", "Chunked request bodies are not supported")
        content_lengths = self.headers.get_all("Content-Length", [])
        if len(content_lengths) != 1 or not re.fullmatch(r"[0-9]{1,10}", content_lengths[0]):
            raise ApiError(411, "length_required", "A single Content-Length header is required")
        length = int(content_lengths[0])
        if length > MAX_BODY_BYTES:
            raise ApiError(413, "body_too_large", "Request body exceeds 1 MiB")
        if self.headers.get_content_type() != "application/json":
            raise ApiError(415, "unsupported_media_type", "Content-Type must be application/json")
        return length

    def handle_expect_100(self) -> bool:
        try:
            if self.path not in ("/api/sync", "/api/personal-sync"):
                raise ApiError(404, "not_found", "Route not found")
            self.authorize_and_length()
        except ApiError as error:
            self.send_api_error(error)
            return False
        self.send_response_only(100)
        self.end_headers()
        return True

    def do_GET(self) -> None:
        if self.path == "/health":
            self.send_json(200, {"status": "ok"})
        elif self.path == "/api/sync":
            self.send_api_error(ApiError(405, "method_not_allowed", "Use POST for synchronization"))
        else:
            self.send_api_error(ApiError(404, "not_found", "Route not found"))

    def do_HEAD(self) -> None:
        if self.path == "/health":
            self.send_json(200, {"status": "ok"}, head_only=True)
        else:
            self.send_json(404, {"error": "not_found", "message": "Route not found"}, head_only=True)

    def do_POST(self) -> None:
        sync_slot = False
        body_read_started = False
        try:
            if self.path != "/api/sync":
                raise ApiError(404, "not_found", "Route not found")
            length = self.authorize_and_length()
            # Bound large payload memory as well as connection/thread count.
            # Acquire before reading the body; queued requests only retain headers.
            sync_slot = self.server.sync_slots.acquire(timeout=5)  # type: ignore[attr-defined]
            if not sync_slot:
                raise ApiError(503, "server_busy", "Server is busy; retry later")
            body_read_started = True
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise ApiError(400, "invalid_json", "Incomplete request body")
            try:
                value = json.loads(raw.decode("utf-8"), object_pairs_hook=reject_duplicate_keys,
                                   parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Invalid JSON number")))
            except (ValueError, UnicodeDecodeError, RecursionError):
                raise ApiError(400, "invalid_json", "Body must be valid UTF-8 JSON") from None
            self.send_json(200, (self.server.service.sync_personal(value) if self.path == "/api/personal-sync" else self.server.service.sync(value)))  # type: ignore[attr-defined]
        except ApiError as error:
            self.send_api_error(error)
            if not body_read_started:
                self.discard_rejected_body()
        except (socket.timeout, TimeoutError):
            self.send_api_error(ApiError(408, "request_timeout", "Request body timed out"))
        except sqlite3.OperationalError:
            logging.exception("Database operation failed")
            self.send_api_error(ApiError(503, "database_unavailable", "Database is unavailable; retry later"))
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True
        except Exception:
            logging.exception("Sync request failed")
            self.send_api_error(ApiError(500, "internal_error", "Request failed; retry later"))
        finally:
            if sync_slot:
                self.server.sync_slots.release()  # type: ignore[attr-defined]


class SyncHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 32

    def __init__(self, service: SyncService) -> None:
        self.service = service
        self.slots = threading.BoundedSemaphore(service.config.max_workers)
        self.sync_slots = threading.BoundedSemaphore(min(2, service.config.max_workers))
        self._achievement_check = 0.0
        super().__init__((service.config.host, service.config.port), SyncHandler)

    def service_actions(self) -> None:
        if time.monotonic() >= self._achievement_check:
            self._achievement_check = time.monotonic() + 60
            try:
                self.service.settle_months()
            except (sqlite3.Error, OSError):
                logging.exception('Monthly settlement failed; will retry without partial cleanup')

    def process_request(self, request: socket.socket, client_address: Any) -> None:
        if not self.slots.acquire(blocking=False):
            try:
                request.settimeout(2)
                request.sendall(b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            except OSError:
                pass
            finally:
                self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request: socket.socket, client_address: Any) -> None:
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


def backup_database(source: Path, destination: Path) -> None:
    source, destination = source.resolve(), destination.resolve()
    if not source.is_file():
        raise ValueError("Source database does not exist")
    if source == destination or destination.exists():
        raise ValueError("Backup destination must be a new file different from the source")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + "." + uuid.uuid4().hex + ".tmp")
    origin: sqlite3.Connection | None = None
    target: sqlite3.Connection | None = None
    try:
        origin = sqlite3.connect(source.as_uri() + "?mode=ro", uri=True, timeout=10)
        target = sqlite3.connect(temporary)
        origin.backup(target, pages=256, sleep=0.05)
        if target.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise ValueError("Backup integrity check failed")
        target.close()
        target = None
        # A new final file prevents accidental replacement of an earlier backup.
        if os.name == "nt":
            # Windows rename is atomic and fails if the target already exists.
            # Creating hard links is unavailable in some Windows sandboxes.
            temporary.rename(destination)
        else:
            # POSIX rename replaces existing files; link instead for no-clobber.
            os.link(temporary, destination)
            temporary.unlink()
    finally:
        if target is not None:
            target.close()
        if origin is not None:
            origin.close()
        if temporary.exists():
            temporary.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=Path(os.environ.get("NAS_TODO_DB", "data/todo.sqlite")))
    parser.add_argument("--host", default=os.environ.get("NAS_TODO_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=os.environ.get("NAS_TODO_PORT", "8787"))
    parser.add_argument("--backup", type=Path, help="Create an online SQLite backup and exit (no token required)")
    arguments = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        if arguments.backup:
            backup_database(arguments.db, arguments.backup)
            logging.info("Backup completed: %s", arguments.backup)
            return 0
        config = Config(arguments.db, os.environ.get("NAS_TODO_TOKEN", ""), arguments.host, arguments.port)
        server = SyncHTTPServer(SyncService(config))
    except (OSError, sqlite3.Error, ValueError) as error:
        logging.error("Startup failed: %s", error)
        return 1
    logging.info("Listening on %s:%s", config.host, server.server_address[1])
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
