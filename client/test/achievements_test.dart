import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_todo/achievement_core.dart';
import 'package:nas_todo/app_controller.dart';
import 'package:nas_todo/main.dart';
import 'package:nas_todo/sync_core.dart';
import 'package:nas_todo/ui/achievements_screen.dart';

class _Store implements DataStore {
  Map<String, dynamic>? state;
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read() async => state;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    if (fail) throw StateError('Disk full');
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _Transport implements SyncTransport {
  Map<String, dynamic>? achievement;
  @override
  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async => {
    'instance_id': 'test-achievement-instance', 'cursor': 0, 'changes': [], 'results': [],
    if (achievement != null) 'achievement': achievement,
  };
}

Map<String, dynamic> _snapshot() {
  final october = calculateAchievement('2026-10', [
    for (var i = 0; i < 5; i++) Task(id: 'o$i', title: 'October', dueDate: '2026-10-01', completed: i < 4),
  ]).toJson();
  october['settled'] = true; october['cleaned'] = 5;
  final november = calculateAchievement('2026-11', [
    const Task(id: 'n', title: 'November', dueDate: '2026-11-02'),
  ]).toJson();
  november['settled'] = true; november['cleaned'] = 1;
  return {'version': 1, 'today': '2026-12-15', 'start_month': '2026-10',
    'live': calculateAchievement('2026-12', []).toJson(), 'settled': [october, november]};
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  test('Exactly 80 percent earns a star; any active failing week makes the month red', () {
    final tasks = [for (var i = 0; i < 5; i++) Task(id: '$i', title: 'Task', dueDate: '2026-10-01', completed: i < 4)];
    var report = calculateAchievement('2026-10', tasks);
    expect(report.stars, 1);
    expect(report.status, 'green');
    expect(report.weeks.first.start, '2026-10-01');
    expect(report.weeks.first.end, '2026-10-04');
    tasks.add(const Task(id: 'fail', title: 'Task', dueDate: '2026-10-05'));
    report = calculateAchievement('2026-10', tasks);
    expect(report.status, 'red');
    expect(report.stars, 1);
  });

  test('Undated, deleted and other-month tasks do not count; dated inbox tasks count', () {
    final report = calculateAchievement('2024-02', const [
      Task(id: 'inbox', title: 'In box', dueDate: '2024-02-29', completed: true),
      Task(id: 'none', title: 'Undated'),
      Task(id: 'deleted', title: 'Deleted', dueDate: '2024-02-29', deleted: true),
      Task(id: 'march', title: 'Next month', dueDate: '2024-03-01'),
    ]);
    expect(report.total, 1);
    expect(report.status, 'green');
    expect(report.weeks.last.end, '2024-02-29');
    expect(calculateAchievement('2025-03', []).weeks.length, 6);
    expect(calculateAchievement('2021-02', []).weeks.length, 4);
  });

  test('An empty month stays grey and inconsistent server counts are rejected', () {
    final report = calculateAchievement('2026-10', []);
    expect(report.status, 'empty');
    expect(report.stars, 0);
    final bad = _snapshot();
    (bad['settled'] as List).first['stars'] = 99;
    expect(() => AchievementState.fromJson(bad), throwsFormatException);
  });

  test('Synced history survives restart and an old backend does not erase it', () async {
    final store = _Store();
    final transport = _Transport()..achievement = _snapshot();
    var engine = SyncEngine(store, transport);
    await engine.load();
    await engine.sync();
    expect(engine.achievementsSupported, isTrue);
    expect(engine.achievement!.settled.first.stars, 1);
    engine = SyncEngine(store, transport);
    await engine.load();
    expect(engine.achievement!.settled.length, 2);
    transport.achievement = null;
    await engine.sync();
    expect(engine.achievementsSupported, isFalse);
    expect(engine.achievement!.settled.length, 2);
  });

  test('Failed durable acknowledgement preserves the previous history for retry', () async {
    final store = _Store();
    final transport = _Transport()..achievement = _snapshot();
    final engine = SyncEngine(store, transport);
    await engine.load();
    store.fail = true;
    await expectLater(engine.sync(), throwsStateError);
    expect(engine.achievement, isNull);
    store.fail = false;
    await engine.sync();
    expect(engine.achievement!.settled.length, 2);
  });

  for (final size in [const Size(320, 568), const Size(1280, 800)]) {
    testWidgets('Twelve month tiles and historical colors fit $size', (tester) async {
      _size(tester, size);
      final engine = SyncEngine(_Store(), _Transport()..achievement = _snapshot());
      await engine.load(); await engine.sync();
      final controller = AppController.forTesting(engine);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AchievementsScreen(controller: controller, clock: () => DateTime(2026, 12, 15)))));
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((w) => w is Material && w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('achievement-month-')), findsNWidgets(12));
      expect(tester.widget<Material>(find.byKey(const ValueKey('achievement-month-2026-10'))).color, const Color(0xff347a54));
      expect(tester.widget<Material>(find.byKey(const ValueKey('achievement-month-2026-11'))).color, const Color(0xffab5151));
      final october = find.byKey(const ValueKey('achievement-month-2026-10'));
      await tester.ensureVisible(october); await tester.tap(october); await tester.pumpAndSettle();
      expect(find.text('10月 · 全周达标'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('New Year automatically opens a new twelve-month year while old history is kept', (tester) async {
    _size(tester, const Size(390, 844));
    var now = DateTime(2026, 12, 31);
    final engine = SyncEngine(_Store(), _Transport()..achievement = _snapshot());
    await engine.load(); await engine.sync();
    final controller = AppController.forTesting(engine);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AchievementsScreen(controller: controller, clock: () => now))));
    await tester.pumpAndSettle();
    now = DateTime(2027, 1, 1);
    await tester.pump(const Duration(minutes: 1)); await tester.pumpAndSettle();
    expect(find.text('2027 年'), findsOneWidget);
    expect(find.byKey(const ValueKey('achievement-month-2027-12')), findsOneWidget);
    await tester.tap(find.byTooltip('上一年')); await tester.pumpAndSettle();
    expect(tester.widget<Material>(find.byKey(const ValueKey('achievement-month-2026-10'))).color, const Color(0xff347a54));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phone navigation exposes achievements without a floating new-task overlay', (tester) async {
    _size(tester, const Size(320, 568));
    final engine = SyncEngine(_Store(), _Transport()); await engine.load();
    final controller = AppController.forTesting(engine); addTearDown(controller.dispose);
    await tester.pumpWidget(PrivateTodoApp(controller: controller)); await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清单与智能视图')); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('成就'), 140,
      scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('成就').last); await tester.pumpAndSettle();
    expect(find.byType(AchievementsScreen), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byKey(const ValueKey('achievement-upgrade-notice')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reading a historical month is not reset by the yearly refresh timer', (tester) async {
    _size(tester, const Size(390, 844));
    final engine = SyncEngine(_Store(), _Transport()..achievement = _snapshot());
    await engine.load(); await engine.sync();
    final controller = AppController.forTesting(engine); addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AchievementsScreen(controller: controller,
      clock: () => DateTime(2026, 12, 15)))));
    await tester.pumpAndSettle();
    final october = find.byKey(const ValueKey('achievement-month-2026-10'));
    await tester.ensureVisible(october); await tester.tap(october); await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 1)); await tester.pumpAndSettle();
    expect(find.text('10月 · 全周达标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
