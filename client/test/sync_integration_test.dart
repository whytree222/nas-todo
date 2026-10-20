import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/storage_io.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/personal_core.dart';

const testToken = 'integration-test-only-not-a-deployment-secret-123456';

class NasServer {
  final Directory directory;
  Process? process;
  String url = '';
  NasServer(this.directory);
  String get python => Platform.environment['NAS_TODO_TEST_PYTHON'] ?? 'python';
  File get database => File('${directory.path}/todo.sqlite');
  File get achievementClock => File('${directory.path}/achievement-clock.txt');
  String get backend => Directory('../server').absolute.path;
  Future<void> start() async {
    process = await Process.start(python, [
      '-B',
      '-u',
      '-c',
      '''
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import datetime as dt
from app import Config, SyncService, SyncHTTPServer, ACHIEVEMENT_TZ
clock_file = Path(sys.argv[4])
clock = lambda: dt.date.fromisoformat(clock_file.read_text().strip()) if clock_file.exists() else dt.datetime.now(ACHIEVEMENT_TZ).date()
server = SyncHTTPServer(SyncService(Config(Path(sys.argv[2]), sys.argv[3], '127.0.0.1', 0), clock=clock))
print('http://127.0.0.1:' + str(server.server_address[1]), flush=True)
server.serve_forever()
''',
      backend,
      database.path,
      testToken,
      achievementClock.path,
    ]);
    final firstLine = Completer<String>();
    process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!firstLine.isCompleted) {
            firstLine.complete(line);
          }
        });
    final errors = StringBuffer();
    process!.stderr.transform(utf8.decoder).listen(errors.write);
    unawaited(
      process!.exitCode.then((code) {
        if (!firstLine.isCompleted) {
          firstLine.completeError(
            StateError('Test NAS startup failed ($code): $errors'),
          );
        }
      }),
    );
    url = await firstLine.future.timeout(const Duration(seconds: 20));
  }

  Future<void> stop() async {
    final running = process;
    process = null;
    if (running == null) {
      return;
    }
    running.kill();
    await running.exitCode.timeout(const Duration(seconds: 10));
  }

  Future<void> backup(File destination) async {
    final result = await Process.run(python, [
      '-B',
      '$backend/app.py',
      '--db',
      database.path,
      '--backup',
      destination.path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('${result.stderr}');
    }
  }

  Future<void> restore(File snapshot) async {
    await stop();
    for (final suffix in ['-wal', '-shm']) {
      final file = File('${database.path}$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }
    await snapshot.copy(database.path);
    await start();
  }
}

class LoseResponseOnce implements SyncTransport {
  final SyncTransport inner;
  bool lose = true;
  LoseResponseOnce(this.inner);
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async {
    final response = await inner.sync(payload);
    if (lose) {
      lose = false;
      throw const SocketException('Response lost after NAS committed');
    }
    return response;
  }
}

class GateTransport implements SyncTransport {
  final SyncTransport inner;
  final entered = Completer<void>();
  final release = Completer<void>();
  GateTransport(this.inner);
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return inner.sync(payload);
  }
}

class FailingStore implements DataStore {
  final DataStore inner;
  bool fail = false;
  int? writesUntilFailure;
  FailingStore(this.inner);
  @override
  Future<Map<String, dynamic>?> read() => inner.read();
  @override
  Future<void> write(Map<String, dynamic> state) async {
    if (fail || writesUntilFailure == 0) {
      throw const FileSystemException('Disk full');
    }
    if (writesUntilFailure != null) {
      writesUntilFailure = writesUntilFailure! - 1;
    }
    await inner.write(state);
  }
}

class PersonalTestTransport implements SyncTransport, PersonalSyncTransport {
  PersonalTestTransport(this.inner);
  final HttpSyncTransport inner;
  bool dropBefore = false;
  void Function()? afterPersonal;
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) =>
      inner.sync(payload);
  @override
  Future<Map<String, dynamic>> syncPersonal(
    Map<String, dynamic> payload,
  ) async {
    if (dropBefore) {
      dropBefore = false;
      throw const SocketException('Offline before personal sync');
    }
    final response = await inner.syncPersonal(payload);
    final callback = afterPersonal;
    afterPersonal = null;
    callback?.call();
    return response;
  }
}

void main() {
  late Directory directory;
  late NasServer nas;
  final transports = <HttpSyncTransport>[];

  Future<SyncEngine> device(
    String name, {
    SyncTransport? transport,
    DataStore? store,
  }) async {
    final actualTransport = transport ?? HttpSyncTransport(nas.url, testToken);
    if (actualTransport is HttpSyncTransport) {
      transports.add(actualTransport);
    }
    final engine = SyncEngine(
      store ?? FileDataStore(File('${directory.path}/$name.json')),
      actualTransport,
    );
    await engine.load();
    return engine;
  }

  setUp(() async {
    final root = Directory(
      Platform.environment['NAS_TODO_TEST_TMP'] ?? 'build/test-state',
    );
    await root.create(recursive: true);
    directory = await root.createTemp('client-');
    nas = NasServer(directory);
    await nas.start();
  });
  tearDown(() async {
    for (final transport in transports) {
      transport.dispose();
    }
    transports.clear();
    await nas.stop();
    await directory.delete(recursive: true);
  });

  test('NAS month-end achievements and cleanup reach both peers and protect an offline edit', () async {
    await nas.achievementClock.writeAsString('2026-10-01', flush: true);
    final a = await device('achievement-a');
    final b = await device('achievement-b');
    for (var index = 0; index < 5; index++) {
      await a.saveTask(
        TaskDraft(
          title: 'Week task $index',
          listName: '工作',
          dueDate: '2026-10-01',
          completed: index < 4,
        ),
      );
    }
    await a.sync();
    await b.sync();
    expect(a.achievement!.live.stars, 1);
    final editing = b.tasks.first;
    await b.saveTask(
      TaskDraft(
        title: 'Offline note kept',
        listName: '工作',
        dueDate: editing.dueDate,
        completed: editing.completed,
      ),
      id: editing.id,
    );
    await nas.achievementClock.writeAsString('2026-11-01', flush: true);
    await a.sync();
    expect(a.tasks, isEmpty);
    expect(a.achievement!.settled.single.stars, 1);
    expect(a.achievement!.settled.single.cleaned, 5);
    await b.sync();
    expect(
      b.achievement!.settled.single.toJson(),
      a.achievement!.settled.single.toJson(),
    );
    expect(b.conflicts.single.local!.title, 'Offline note kept');
    expect(b.conflicts.single.remote!.deleted, isTrue);
    await b.resolveConflict(editing.id, keepLocal: false);
    expect(b.tasks, isEmpty);
    final reopened = await device('achievement-a');
    expect(reopened.achievement!.settled.single.stars, 1);
  });

  test(
    'offline edits survive restart and coalesce without uploading',
    () async {
      final a = await device('a');
      await a.saveTask(const TaskDraft(title: '买牛奶', listName: '生活'));
      final id = a.tasks.single.id;
      await a.saveTask(
        const TaskDraft(title: '买两瓶牛奶', listName: '生活', priority: 2),
        id: id,
      );
      final reopened = await device('a');
      expect(reopened.tasks.single.title, '买两瓶牛奶');
      expect(reopened.pendingCount, 1);
      final b = await device('b');
      await b.sync();
      expect(b.tasks, isEmpty);
      await reopened.sync();
      await b.sync();
      expect(b.tasks.single.title, '买两瓶牛奶');
      expect(reopened.pendingCount, 0);
    },
  );

  test(
    'two offline edits retain both versions until explicit choice',
    () async {
      final a = await device('a');
      final b = await device('b');
      await a.saveTask(const TaskDraft(title: '共享待办'));
      await a.sync();
      await b.sync();
      final id = a.tasks.single.id;
      await a.saveTask(const TaskDraft(title: '电脑编辑'), id: id);
      await b.saveTask(const TaskDraft(title: '手机离线编辑'), id: id);
      await a.sync();
      await b.sync();
      expect(b.tasks.single.title, '手机离线编辑');
      expect(b.conflicts.single.remote!.title, '电脑编辑');
      final reopened = await device('b');
      expect(reopened.conflicts.single.local!.title, '手机离线编辑');
      await reopened.resolveConflict(id, keepLocal: true);
      await reopened.sync();
      await a.sync();
      expect(a.tasks.single.title, '手机离线编辑');
      expect(reopened.conflicts, isEmpty);
    },
  );

  test(
    'keeping NAS version discards only explicitly rejected local edit',
    () async {
      final a = await device('a');
      final b = await device('b');
      await a.saveTask(const TaskDraft(title: '原始'));
      await a.sync();
      await b.sync();
      final id = a.tasks.single.id;
      await a.saveTask(const TaskDraft(title: 'NAS版本'), id: id);
      await a.sync();
      await b.saveTask(const TaskDraft(title: '本机版本'), id: id);
      await b.sync();
      await b.resolveConflict(id, keepLocal: false);
      expect(b.tasks.single.title, 'NAS版本');
      expect(b.pendingCount, 0);
    },
  );

  test('completion and deletion propagate between devices', () async {
    final a = await device('a');
    final b = await device('b');
    await a.saveTask(const TaskDraft(title: '完成任务'));
    await a.sync();
    await b.sync();
    final id = b.tasks.single.id;
    await b.saveTask(const TaskDraft(title: '完成任务', completed: true), id: id);
    await b.sync();
    await a.sync();
    expect(a.tasks.single.completed, isTrue);
    await a.deleteTask(id);
    await a.sync();
    await b.sync();
    expect(a.tasks, isEmpty);
    expect(b.tasks, isEmpty);
    expect(b.conflicts, isEmpty);
  });

  test(
    'local edit after remote deletion recreates a separate task only by choice',
    () async {
      final a = await device('a');
      final b = await device('b');
      await a.saveTask(const TaskDraft(title: '删除冲突'));
      await a.sync();
      await b.sync();
      final oldId = a.tasks.single.id;
      await a.deleteTask(oldId);
      await a.sync();
      await b.saveTask(const TaskDraft(title: '手机保留的内容'), id: oldId);
      await b.sync();
      expect(b.conflicts.single.remote!.deleted, isTrue);
      await b.resolveConflict(oldId, keepLocal: true);
      expect(b.tasks.single.id, isNot(oldId));
      await b.sync();
      await a.sync();
      expect(a.tasks.single.title, '手机保留的内容');
      expect(a.tasks.single.id, b.tasks.single.id);
    },
  );

  test(
    'lost response retries same operation without a duplicate task',
    () async {
      final http = HttpSyncTransport(nas.url, testToken);
      transports.add(http);
      final losing = LoseResponseOnce(http);
      final a = await device('a', transport: losing);
      await a.saveTask(const TaskDraft(title: '响应丢失'));
      await expectLater(a.sync(), throwsA(isA<SocketException>()));
      expect(a.pendingCount, 1);
      final reopened = await device('a');
      await reopened.sync();
      expect(reopened.tasks.single.version, 1);
      final b = await device('b');
      await b.sync();
      expect(b.tasks.length, 1);
      expect(b.tasks.single.version, 1);
    },
  );

  test('editing after a lost response preserves the original retry then uploads the new edit', () async {
    final http = HttpSyncTransport(nas.url, testToken);
    transports.add(http);
    final a = await device('a', transport: LoseResponseOnce(http));
    await a.saveTask(const TaskDraft(title: '第一次内容'));
    final id = a.tasks.single.id;
    await expectLater(a.sync(), throwsA(isA<SocketException>()));
    await a.saveTask(const TaskDraft(title: '响应丢失后继续编辑'), id: id);
    await a.saveTask(const TaskDraft(title: '最终本机内容'), id: id);
    expect(a.pendingCount, 2);
    final reopened = await device('a');
    await reopened.sync();
    expect(reopened.conflicts, isEmpty);
    expect(reopened.pendingCount, 0);
    expect(reopened.tasks.single.title, '最终本机内容');
    expect(reopened.tasks.single.version, 2);
  });

  test('deleting after a lost create response retries the create before its deletion', () async {
    final http = HttpSyncTransport(nas.url, testToken);
    transports.add(http);
    final a = await device('a', transport: LoseResponseOnce(http));
    await a.saveTask(const TaskDraft(title: '创建后删除'));
    final id = a.tasks.single.id;
    await expectLater(a.sync(), throwsA(isA<SocketException>()));
    await a.deleteTask(id);
    await a.sync();
    expect(a.tasks, isEmpty);
    expect(a.conflicts, isEmpty);
    expect(a.pendingCount, 0);
    final b = await device('b');
    await b.sync();
    expect(b.tasks, isEmpty);
  });

  test('deleting a never-sent offline creation cancels it without a server conflict', () async {
    final a = await device('a');
    await a.saveTask(const TaskDraft(title: '只在本地'));
    await a.deleteTask(a.tasks.single.id);
    expect(a.pendingCount, 0);
    await a.sync();
    expect(a.conflicts, isEmpty);
    final b = await device('b');
    await b.sync();
    expect(b.tasks, isEmpty);
  });

  test(
    'edit queued during a sync cannot be erased by its acknowledgement',
    () async {
      final http = HttpSyncTransport(nas.url, testToken);
      transports.add(http);
      final gate = GateTransport(http);
      final a = await device('a', transport: gate);
      await a.saveTask(const TaskDraft(title: '上传中的版本'));
      final id = a.tasks.single.id;
      final sync = a.sync();
      await gate.entered.future;
      final edit = a.saveTask(const TaskDraft(title: '上传时继续编辑'), id: id);
      gate.release.complete();
      await sync;
      await edit;
      expect(a.tasks.single.title, '上传时继续编辑');
      expect(a.pendingCount, 1);
      await a.sync();
      final b = await device('b');
      await b.sync();
      expect(b.tasks.single.title, '上传时继续编辑');
      expect(a.conflicts, isEmpty);
    },
  );

  test('invalid credentials preserve every local modification', () async {
    final bad = HttpSyncTransport(
      nas.url,
      'wrong-token-which-is-long-enough-123456',
    );
    transports.add(bad);
    final a = await device('a', transport: bad);
    await a.saveTask(const TaskDraft(title: '没有丢失'));
    await expectLater(a.sync(), throwsA(isA<SyncServerException>()));
    expect(a.tasks.single.title, '没有丢失');
    expect(a.pendingCount, 1);
  });

  test('completion during a pull changes only completion, retaining the latest remote content', () async {
    final a = await device('a');
    final originalB = await device('b');
    await a.saveTask(const TaskDraft(title: '旧标题'));
    await a.sync();
    await originalB.sync();
    final id = a.tasks.single.id;
    await a.saveTask(
      const TaskDraft(title: 'NAS新标题', note: 'NAS新备注'),
      id: id,
    );
    await a.sync();
    final http = HttpSyncTransport(nas.url, testToken);
    transports.add(http);
    final gate = GateTransport(http);
    final b = await device('b', transport: gate);
    final sync = b.sync();
    await gate.entered.future;
    final completion = b.setCompleted(id, true);
    gate.release.complete();
    await sync;
    await completion;
    await b.sync();
    await a.sync();
    expect(a.tasks.single.title, 'NAS新标题');
    expect(a.tasks.single.note, 'NAS新备注');
    expect(a.tasks.single.completed, isTrue);
    expect(b.conflicts, isEmpty);
  });

  test('scheduling during a pull retains latest NAS content and synchronizes its new date', () async {
    final a = await device('a');
    final originalB = await device('b');
    await a.saveTask(const TaskDraft(title: '未安排的旧内容'));
    await a.sync();
    await originalB.sync();
    final id = a.tasks.single.id;
    await a.saveTask(
      const TaskDraft(
        title: 'NAS新内容',
        note: '最新备注',
        listName: '工作',
        priority: 2,
        completed: true,
      ),
      id: id,
    );
    await a.sync();
    final http = HttpSyncTransport(nas.url, testToken);
    transports.add(http);
    final gate = GateTransport(http);
    final b = await device('b', transport: gate);
    final sync = b.sync();
    await gate.entered.future;
    final scheduling = b.scheduleTask(id, '2024-02-29');
    gate.release.complete();
    await sync;
    await scheduling;
    await b.sync();
    await a.sync();
    final task = a.tasks.single;
    expect(
      [
        task.id,
        task.title,
        task.note,
        task.listName,
        task.priority,
        task.completed,
        task.dueDate,
      ],
      [id, 'NAS新内容', '最新备注', '工作', 2, true, '2024-02-29'],
    );
    expect(b.conflicts, isEmpty);
    expect(b.pendingCount, 0);
  });

  test('a date received during a pull cannot be overwritten by an outdated unscheduled drag', () async {
    final a = await device('a');
    final originalB = await device('b');
    await a.saveTask(const TaskDraft(title: '未安排'));
    await a.sync();
    await originalB.sync();
    final id = a.tasks.single.id;
    await a.saveTask(
      const TaskDraft(title: '已安排', dueDate: '2024-03-01'),
      id: id,
    );
    await a.sync();
    final http = HttpSyncTransport(nas.url, testToken);
    transports.add(http);
    final gate = GateTransport(http);
    final b = await device('b', transport: gate);
    final sync = b.sync();
    await gate.entered.future;
    final scheduling = b.scheduleTask(id, '2024-02-29');
    final rejected = expectLater(scheduling, throwsA(isA<StateError>()));
    gate.release.complete();
    await sync;
    await rejected;
    expect(b.tasks.single.dueDate, '2024-03-01');
    expect(b.pendingCount, 0);
  });

  test('more than 100 changes upload in durable bounded batches', () async {
    final a = await device('a');
    for (var i = 0; i < 105; i++) {
      await a.saveTask(TaskDraft(title: '任务$i'));
    }
    await a.sync();
    final b = await device('b');
    await b.sync();
    expect(b.tasks.length, 105);
    expect(a.pendingCount, 0);
  });

  test(
    'large Chinese notes are batched below HTTP request size limit',
    () async {
      final a = await device('a');
      final note = List.filled(10000, '界').join();
      for (var i = 0; i < 36; i++) {
        await a.saveTask(TaskDraft(title: '长备注$i', note: note));
      }
      await a.sync();
      final b = await device('b');
      await b.sync();
      expect(b.tasks.length, 36);
      expect(a.pendingCount, 0);
    },
  );

  test(
    'a failed durable local save restores its previous memory state',
    () async {
      final store = FailingStore(
        FileDataStore(File('${directory.path}/a.json')),
      );
      final a = await device('a', store: store);
      await a.saveTask(const TaskDraft(title: '已保存'));
      store.fail = true;
      await expectLater(
        a.saveTask(const TaskDraft(title: '未保存')),
        throwsA(isA<FileSystemException>()),
      );
      expect(a.tasks.single.title, '已保存');
      expect(a.pendingCount, 1);
    },
  );

  test(
    'a failed acknowledgement save retries safely from the durable outbox',
    () async {
      final store = FailingStore(
        FileDataStore(File('${directory.path}/a.json')),
      );
      final a = await device('a', store: store);
      await a.saveTask(const TaskDraft(title: 'NAS已收到'));
      store.writesUntilFailure = 1;
      await expectLater(a.sync(), throwsA(isA<FileSystemException>()));
      expect(a.pendingCount, 1);
      store.writesUntilFailure = null;
      await a.sync();
      expect(a.tasks.single.version, 1);
      expect(a.pendingCount, 0);
    },
  );

  test(
    'damaged primary recovers backup without overwriting the good backup',
    () async {
      final a = await device('a');
      await a.saveTask(const TaskDraft(title: '备份内容'));
      await a.saveTask(const TaskDraft(title: '最新内容'));
      final file = File('${directory.path}/a.json');
      await file.writeAsString('{broken');
      final reopened = await device('a');
      expect(reopened.tasks.single.title, '备份内容');
      await reopened.saveTask(const TaskDraft(title: '恢复后新增'));
      final backup =
          jsonDecode(await File('${file.path}.bak').readAsString()) as Map;
      expect((backup['tasks'] as List).length, 1);
    },
  );

  test('restoring older NAS backup replaces acknowledged cache and preserves offline edit', () async {
    final http = HttpSyncTransport(nas.url, testToken);
    transports.add(http);
    final a = await device('a', transport: http);
    await a.saveTask(const TaskDraft(title: '备份时版本'));
    await a.sync();
    final id = a.tasks.single.id;
    final snapshot = File('${directory.path}/snapshot.sqlite');
    await nas.backup(snapshot);
    await a.saveTask(const TaskDraft(title: '备份后NAS版本'), id: id);
    await a.sync();
    await a.saveTask(const TaskDraft(title: '备份后新建且已同步'));
    await a.sync();
    await a.saveTask(const TaskDraft(title: '还没上传的本机待办'));
    await nas.restore(snapshot);
    http.configure(nas.url, testToken);
    await a.sync();
    expect(a.tasks.map((t) => t.title).toSet(), {'备份时版本', '还没上传的本机待办'});
    expect(a.pendingCount, 0);
  });

  test(
    'a different NAS database cannot receive edits from an existing binding',
    () async {
      final http = HttpSyncTransport(nas.url, testToken);
      transports.add(http);
      final a = await device('a', transport: http);
      await a.saveTask(const TaskDraft(title: '原数据库'));
      await a.sync();
      await a.saveTask(const TaskDraft(title: '不应传到错误NAS'));
      final otherDirectory = Directory('${directory.path}/other');
      await otherDirectory.create();
      final other = NasServer(otherDirectory);
      await other.start();
      try {
        http.configure(other.url, testToken);
        await expectLater(
          a.sync(),
          throwsA(
            isA<SyncServerException>().having(
              (e) => e.code,
              'code',
              'instance_mismatch',
            ),
          ),
        );
        expect(a.pendingCount, 1);
        final observer = HttpSyncTransport(other.url, testToken);
        transports.add(observer);
        final response = await observer.sync({
          'instance_id': null,
          'cursor': 0,
          'operations': [],
        });
        expect(response['changes'], isEmpty);
      } finally {
        await other.stop();
      }
    },
  );
  test('Personal hierarchy, tags, recurrence and habits reach a second real device and survive restart', () async {
    final a = await device('personal-a'), b = await device('personal-b');
    await a.saveTask(const TaskDraft(title: '父待办', tags: ['学习']));
    final parent = a.tasks.single;
    await a.saveTask(
      TaskDraft(
        title: '重复子任务',
        parentId: parent.id,
        tags: ['阅读'],
        dueDate: '2099-10-20',
        repeatRule: const TaskRepeatRule(frequency: 'daily'),
      ),
    );
    final child = a.tasks.last;
    await a.sync();
    await b.sync();
    expect(b.tasks.last.parentId, parent.id);
    expect(b.tasks.last.tags, ['阅读']);
    await a.setCompleted(child.id, true);
    await a.sync();
    await b.sync();
    final next = b.tasks.singleWhere(
      (task) => task.id != child.id && task.parentId == parent.id,
    );
    expect(next.dueDate, '2099-10-21');
    expect(next.repeatRule!.frequency, 'daily');
    await a.saveHabit(const HabitDraft(name: '阅读', goalType: 'count', goal: 4));
    await a.setHabitValue(a.habits.single.id, '2026-10-20', 3);
    await a.sync();
    await b.sync();
    expect(b.habitCheckIns.single.value, 3);
    final reopened = await device('personal-a');
    expect(reopened.tasks.length, 3);
    expect(reopened.habits.single.name, '阅读');
    expect(reopened.habitCheckIns.single.value, 3);
    expect(reopened.pendingCount, 0);
  });

  test('Interrupted metadata update cannot generate an unwanted repeat and restart releases the saved intent', () async {
    final inner = HttpSyncTransport(nas.url, testToken);
    transports.add(inner);
    final transport = PersonalTestTransport(inner);
    final a = await device('repeat-intent', transport: transport);
    await a.saveTask(
      const TaskDraft(
        title: '取消重复',
        dueDate: '2099-10-20',
        repeatRule: TaskRepeatRule(frequency: 'daily'),
      ),
    );
    await a.sync();
    final task = a.tasks.single;
    await a.saveTask(
      TaskDraft.fromTask(
        task,
      ).copyWith(dueDate: '2099-10-25', completed: true, clearRepeatRule: true),
      id: task.id,
    );
    transport.dropBefore = true;
    await expectLater(a.sync(), throwsA(isA<SocketException>()));
    expect(a.pendingCount, greaterThan(0));
    final b = await device('observer-repeat');
    await b.sync();
    expect(
      b.tasks.length,
      1,
      reason: 'Other clients cannot bypass the durable recurrence hold',
    );
    final reopened = await device('repeat-intent');
    await reopened.sync();
    await b.sync();
    expect(reopened.pendingCount, 0);
    expect(b.tasks.length, 1);
    expect(b.tasks.single.repeatRule, isNull);
    expect(b.tasks.single.dueDate, '2099-10-25');
  });

  test('Concurrent check-ins preserve both versions and local resolution converges', () async {
    final a = await device('habit-conflict-a'),
        b = await device('habit-conflict-b');
    await a.saveHabit(const HabitDraft(name: '喝水', goalType: 'count', goal: 8));
    await a.sync();
    await b.sync();
    final id = a.habits.single.id;
    await a.setHabitValue(id, '2026-10-20', 2);
    await b.setHabitValue(id, '2026-10-20', 3);
    await a.sync();
    await b.sync();
    expect(b.personalConflicts, hasLength(1));
    final conflict = b.personalConflicts.single;
    expect(conflict.local!.data['value'], 3);
    expect(conflict.remote!.data['value'], 2);
    await b.resolvePersonalConflict(
      conflict.kind,
      conflict.id,
      keepLocal: true,
    );
    await b.sync();
    await a.sync();
    expect(a.habitCheckIns.single.value, 3);
    expect(b.personalConflicts, isEmpty);
  });

  test('A failed durable personal acknowledgement replays once without duplicating history', () async {
    final inner = HttpSyncTransport(nas.url, testToken);
    transports.add(inner);
    final transport = PersonalTestTransport(inner);
    final store = FailingStore(
      FileDataStore(File('${directory.path}/personal-disk.json')),
    );
    final a = await device('personal-disk', transport: transport, store: store);
    await a.saveHabit(const HabitDraft(name: '运动'));
    final id = a.habits.single.id;
    await a.setHabitValue(id, '2026-10-20', 1);
    transport.afterPersonal = () => store.fail = true;
    await expectLater(a.sync(), throwsA(isA<FileSystemException>()));
    expect(a.pendingCount, 2);
    store.fail = false;
    final reopened = await device('personal-disk');
    await reopened.sync();
    final b = await device('personal-disk-b');
    await b.sync();
    expect(reopened.pendingCount, 0);
    expect(b.habits, hasLength(1));
    expect(b.habitCheckIns, hasLength(1));
    expect(b.habitCheckIns.single.value, 1);
  });
}
