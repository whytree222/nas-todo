"""HTTP, transaction, offline-device, restart, and backup regression tests."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import copy
import http.client
import json
import os
from pathlib import Path
import sqlite3
import socket
import sys
import tempfile
import threading
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import Config, MAX_BODY_BYTES, SyncHTTPServer, SyncService, backup_database


TOKEN = "test-only-token-" + "x" * 40


def operation(*, task_id: str | None = None, base: int = 0, action: str = "upsert",
              title: str = "待办：买牛奶", **data_changes) -> dict:
    data = {"title": title, "note": "离线也可以编辑", "list_name": "收件箱", "due_date": "2026-10-08",
            "priority": 1, "completed": False}
    data.update(data_changes)
    return {"op_id": str(uuid.uuid4()), "task_id": task_id or str(uuid.uuid4()),
            "base_version": base, "action": action, "data": data}


class SyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(dir=os.environ.get("NAS_TODO_TEST_TMP"))
        self.db = Path(self.directory.name) / "data" / "todo.sqlite"
        self.start_server()
        status, response = self.sync([])
        self.assertEqual(status, 200)
        self.instance_id = response["instance_id"]

    def start_server(self, **config_changes) -> None:
        self.service = SyncService(Config(self.db, TOKEN, host="127.0.0.1", port=0, **config_changes))
        self.server = SyncHTTPServer(self.service)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def stop_server(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def tearDown(self) -> None:
        self.stop_server()
        self.directory.cleanup()

    def request(self, value=None, *, raw: bytes | None = None, token: str | None = TOKEN,
                method="POST", path="/api/sync", extra_headers=None) -> tuple[int, dict]:
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        headers = {"Content-Type": "application/json"}
        if token is not None:
            headers["Authorization"] = "Bearer " + token
        if extra_headers:
            headers.update(extra_headers)
        body = raw if raw is not None else json.dumps(value, ensure_ascii=False).encode("utf-8")
        try:
            connection.request(method, path, body=body if method == "POST" else None, headers=headers)
            response = connection.getresponse()
            payload = response.read()
            return response.status, json.loads(payload) if payload else {}
        finally:
            connection.close()

    def sync(self, operations, *, cursor=0, instance_id=None):
        return self.request({"instance_id": instance_id, "cursor": cursor, "operations": operations})

    def test_health_and_authentication(self):
        self.assertEqual(self.request(method="GET", path="/health", token=None), (200, {"status": "ok"}))
        for token in (None, "wrong"):
            status, response = self.request({}, token=token)
            self.assertEqual(status, 401)
            self.assertEqual(response["error"], "unauthorized")
            self.assertNotIn(TOKEN, json.dumps(response))
        self.assertEqual(self.request(method="GET")[0], 405)
        self.assertEqual(self.request(method="POST", path="/unknown")[0], 404)

    def test_no_default_or_short_token(self):
        for token in ("", "short", "x" * 32 + " ", "汉" * 32):
            with self.assertRaises(ValueError):
                SyncService(Config(self.db, token))

    def test_personal_route_authentication_and_capability(self):
        status, base = self.sync([])
        self.assertEqual(status, 200)
        self.assertEqual(base["personal_sync"], 1)
        payload = {"instance_id": self.instance_id, "cursor": 0, "operations": []}
        for token in (None, "wrong"):
            status, response = self.request(payload, path="/api/personal-sync", token=token)
            self.assertEqual(status, 401)
            self.assertEqual(response["error"], "unauthorized")
        status, response = self.request(payload, path="/api/personal-sync")
        self.assertEqual(status, 200)
        self.assertEqual(response["instance_id"], self.instance_id)
        self.assertEqual(response["changes"], [])
        self.assertEqual(self.request(method="GET", path="/api/personal-sync")[0], 405)

    def test_unauthorized_upload_delivers_complete_error_without_reset(self):
        # Deliberately start the body after the server has rejected the headers.
        # Closing with its upload unread can otherwise reset the connection and
        # turn a framed 401 response into a platform-dependent transport failure.
        body = json.dumps({"instance_id": None, "cursor": 0, "operations": [],
                           "padding": "x" * (768 * 1024)}).encode("utf-8")
        headers = ("POST /api/sync HTTP/1.1\r\nHost: localhost\r\n"
                   "Authorization: Bearer wrong-token\r\nContent-Type: application/json\r\n"
                   f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n").encode("ascii")
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as connection:
            connection.sendall(headers + body[:1])
            response = http.client.HTTPResponse(connection)
            try:
                response.begin()
                self.assertEqual(response.status, 401)
                connection.sendall(body[1:])
                error = json.loads(response.read())
                self.assertEqual(error["error"], "unauthorized")
            finally:
                response.close()
        self.assertEqual(self.sync([])[1]["cursor"], 0)

    def test_create_update_and_incremental_pull(self):
        first = operation()
        status, response = self.sync([first], instance_id=self.instance_id)
        self.assertEqual(status, 200)
        self.assertEqual(response["cursor"], 1)
        task = response["results"][0]["task"]
        self.assertEqual(task["id"], first["task_id"])
        self.assertEqual(task["version"], 1)
        self.assertFalse(task["deleted"])
        self.assertFalse(task["completed"])
        self.assertTrue(task["updated_at"].endswith("Z"))
        update = operation(task_id=task["id"], base=1, title="已买牛奶", completed=True, due_date=None)
        status, response = self.sync([update], cursor=1, instance_id=self.instance_id)
        self.assertEqual(status, 200)
        self.assertEqual(response["cursor"], 2)
        self.assertEqual(response["changes"][0]["title"], "已买牛奶")
        self.assertEqual(response["changes"][0]["version"], 2)
        self.assertEqual(self.sync([], cursor=2, instance_id=self.instance_id)[1]["changes"], [])

    def test_two_offline_devices_cannot_silently_overwrite(self):
        first = operation()
        self.sync([first])
        edits = [operation(task_id=first["task_id"], base=1, title=title) for title in ("手机编辑", "电脑编辑")]
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(lambda edit: self.sync([edit], cursor=1, instance_id=self.instance_id), edits))
        self.assertTrue(all(status == 200 for status, _ in responses))
        statuses = sorted(response["results"][0]["status"] for _, response in responses)
        self.assertEqual(statuses, ["applied", "conflict"])
        status, full = self.sync([])
        self.assertEqual(full["cursor"], 2)
        self.assertEqual(len(full["changes"]), 1)
        self.assertEqual(full["changes"][0]["version"], 2)
        loser = next(response for _, response in responses if response["results"][0]["status"] == "conflict")
        self.assertEqual(loser["results"][0]["task"], full["changes"][0])

    def test_replay_is_idempotent_even_after_later_updates(self):
        first = operation()
        _, initial = self.sync([first])
        _, retry = self.sync([first])
        self.assertEqual(retry["cursor"], 1)
        self.assertEqual(retry["results"], initial["results"])
        self.sync([operation(task_id=first["task_id"], base=1, title="later")])
        _, retry = self.sync([first], cursor=2, instance_id=self.instance_id)
        self.assertEqual(retry["cursor"], 2)
        self.assertEqual(retry["results"], initial["results"])
        self.assertEqual(retry["changes"], [])

    def test_payload_reuse_rejects_whole_batch_before_writes(self):
        first = operation()
        self.sync([first])
        tampered = copy.deepcopy(first)
        tampered["data"]["title"] = "reused operation ID"
        new = operation(title="must not be created")
        status, response = self.sync([new, tampered])
        self.assertEqual((status, response["error"]), (409, "op_id_reused"))
        _, full = self.sync([])
        self.assertEqual(full["cursor"], 1)
        self.assertEqual(len(full["changes"]), 1)
        self.assertEqual(self.sync([new])[1]["results"][0]["status"], "applied")

    def test_deleted_task_is_a_tombstone_and_never_resurrects(self):
        first = operation()
        self.sync([first])
        delete = operation(task_id=first["task_id"], base=1, action="delete", title="not retained")
        status, response = self.sync([delete], cursor=1, instance_id=self.instance_id)
        self.assertEqual(status, 200)
        tombstone = response["changes"][0]
        self.assertTrue(tombstone["deleted"])
        self.assertEqual(tombstone["version"], 2)
        self.assertEqual(tombstone["title"], first["data"]["title"])
        for base in (0, 1, 2):
            for action in ("upsert", "delete"):
                status, response = self.sync([operation(task_id=first["task_id"], base=base, action=action)])
                self.assertEqual(status, 200)
                self.assertEqual(response["cursor"], 2)
                self.assertEqual(response["results"][0]["status"], "conflict")
                self.assertEqual(response["results"][0]["task"], tombstone)
        self.assertEqual(self.sync([operation(title="new copy")])[1]["cursor"], 3)

    def test_missing_task_delete_or_stale_create_conflicts(self):
        for edit in (operation(action="delete"), operation(base=1)):
            status, response = self.sync([edit])
            self.assertEqual(status, 200)
            self.assertEqual(response["results"], [{"op_id": edit["op_id"], "status": "conflict", "task": None}])
            self.assertEqual(response["cursor"], 0)

    def test_validation_is_atomic(self):
        first, invalid = operation(), operation()
        invalid["data"]["due_date"] = "2026-02-30"
        self.assertEqual(self.sync([first, invalid])[0], 400)
        self.assertEqual(self.sync([])[1]["cursor"], 0)
        invalid["data"]["due_date"] = "2026-02-28"
        status, response = self.sync([first, invalid])
        self.assertEqual(status, 200)
        self.assertEqual([item["status"] for item in response["results"]], ["applied", "applied"])

    def test_exact_types_and_length_validation(self):
        invalid_fields = [("completed", 1), ("priority", True), ("priority", 1.0), ("priority", 3),
                          ("title", "  "), ("title", "a" * 201), ("note", "a" * 10_001),
                          ("list_name", "a" * 61), ("due_date", "2026-1-01"), ("due_date", "0000-01-01"),
                          ("title", "\ud800")]
        for key, value in invalid_fields:
            with self.subTest(key=key, value=str(value)[:50]):
                edit = operation()
                edit["data"][key] = value
                # ensure_ascii handles intentionally malformed Unicode JSON safely.
                raw = json.dumps({"instance_id": None, "cursor": 0, "operations": [edit]}).encode()
                self.assertEqual(self.request(raw=raw)[0], 400)
        for key, value in (("base_version", True), ("base_version", -1), ("task_id", "invalid")):
            edit = operation()
            edit[key] = value
            self.assertEqual(self.sync([edit])[0], 400)
        self.assertEqual(self.sync([], cursor=True)[0], 400)
        self.assertEqual(self.sync([])[1]["cursor"], 0)

    def test_instance_and_future_cursor_fail_before_mutation(self):
        edit = operation()
        for cursor, instance, expected in ((0, str(uuid.uuid4()), "instance_mismatch"),
                                            (1, self.instance_id, "future_cursor"),
                                            (1, None, "instance_required")):
            status, response = self.sync([edit], cursor=cursor, instance_id=instance)
            self.assertEqual((status, response["error"]), (409, expected))
        self.assertEqual(self.sync([])[1]["cursor"], 0)
        self.assertEqual(self.sync([edit])[1]["results"][0]["status"], "applied")

    def test_operation_batch_limits_and_duplicate_ids(self):
        self.assertEqual(self.sync([operation() for _ in range(101)])[0], 400)
        edit = operation()
        self.assertEqual(self.sync([edit, edit])[0], 400)
        self.assertEqual(self.sync([])[1]["cursor"], 0)

    def test_bad_json_is_rejected(self):
        for raw in (b"{", b"[]", b'{}', b'{"cursor":0,"cursor":0}',
                    b'{"instance_id":null,"cursor":NaN,"operations":[]}', b"\xff",
                    b"[" * 1500 + b"]" * 1500):
            with self.subTest(raw=raw[:50]):
                self.assertEqual(self.request(raw=raw)[0], 400)

    def test_request_size_and_content_type(self):
        self.assertEqual(self.request({}, extra_headers={"Content-Type": "text/plain"})[0], 415)
        self.assertEqual(self.request(raw=b"{}", extra_headers={"Content-Length": str(MAX_BODY_BYTES + 1)})[0], 413)
        self.assertEqual(self.request({}, extra_headers={"Transfer-Encoding": "chunked"})[0], 400)

    def test_task_capacity_rolls_back_and_includes_tombstones(self):
        self.stop_server()
        self.start_server(max_tasks=2)
        first, second = operation(), operation()
        status, response = self.sync([first, second, operation()])
        self.assertEqual((status, response["error"]), (409, "capacity_exceeded"))
        self.assertEqual(self.sync([])[1]["cursor"], 0)
        self.sync([first, second])
        self.sync([operation(task_id=first["task_id"], base=1, action="delete")])
        status, response = self.sync([operation()])
        self.assertEqual((status, response["error"]), (409, "capacity_exceeded"))

    def test_data_capacity_rolls_back_all_operations(self):
        self.stop_server()
        self.start_server(max_data_bytes=600)
        first = operation(note="x" * 150)
        second = operation(note="x" * 450)
        status, response = self.sync([first, second])
        self.assertEqual((status, response["error"]), (409, "capacity_exceeded"))
        self.assertEqual(self.sync([])[1]["cursor"], 0)
        self.assertEqual(self.sync([first])[1]["results"][0]["status"], "applied")

    def test_restart_preserves_cursor_instance_and_replay_history(self):
        edit = operation()
        _, initial = self.sync([edit])
        self.stop_server()
        self.start_server()
        _, response = self.sync([edit], cursor=1, instance_id=self.instance_id)
        self.assertEqual(response["instance_id"], self.instance_id)
        self.assertEqual(response["cursor"], 1)
        self.assertEqual(response["results"], initial["results"])

    def test_online_backup_captures_live_wal_and_operation_history(self):
        edit = operation()
        # Hold a reader open so SQLite retains a live WAL while the backup runs.
        keeper = sqlite3.connect(self.db)
        try:
            keeper.execute("BEGIN")
            keeper.execute("SELECT * FROM tasks").fetchall()
            self.sync([edit])
            destination = Path(self.directory.name) / "backups" / "snapshot.sqlite"
            backup_database(self.db, destination)
            with closing(sqlite3.connect(destination)) as backup:
                self.assertEqual(backup.execute("PRAGMA quick_check").fetchone()[0], "ok")
                self.assertEqual(backup.execute("SELECT id FROM tasks").fetchone()[0], edit["task_id"])
                self.assertEqual(backup.execute("SELECT op_id FROM operations").fetchone()[0], edit["op_id"])
                self.assertEqual(backup.execute("SELECT value FROM metadata WHERE key='cursor'").fetchone()[0], "1")
            with self.assertRaises(ValueError):
                backup_database(self.db, destination)
            with self.assertRaises(ValueError):
                backup_database(self.db, self.db)
        finally:
            keeper.close()


if __name__ == "__main__":
    unittest.main()
