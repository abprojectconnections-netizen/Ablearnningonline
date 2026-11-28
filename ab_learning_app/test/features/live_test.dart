import 'dart:typed_data';

import 'package:ab_learning_app/core/di/app_dependencies.dart';
import 'package:ab_learning_app/core/network/rest_client.dart';
import 'package:ab_learning_app/core/network/token_store.dart';
import 'package:ab_learning_app/features/live/data/live_repository.dart';
import 'package:ab_learning_app/features/live/presentation/instructor_live_screen.dart';
import 'package:ab_learning_app/features/live/presentation/live_detail_screen.dart';
import 'package:ab_learning_app/features/live/presentation/live_list_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_helpers.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status);

  int status;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final String body;
    if (options.path == '/live') {
      body = '{"items":[{"id":4,"title":"Go","instructor":"Ann",'
          '"scheduled_at":"2026-12-01T12:30:00Z","duration_minutes":45,'
          '"status":"upcoming","attendees":3,"registered":true}]}';
    } else {
      body = '{"id":4,"title":"Go","status":"live",'
          '"stream_url":"https://meet.example/go",'
          '"questions":[{"id":9,"question":"q","upvotes":2}]}';
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

LiveSession _session({
  int id = 1,
  String status = 'upcoming',
  bool registered = false,
  bool mine = false,
  double price = 0,
  String streamUrl = '',
}) {
  return LiveSession(
    id: id,
    title: 'Go concurrency',
    instructor: 'Ann',
    scheduledAt: DateTime(2026, 12, 1, 19, 30),
    durationMinutes: 60,
    status: status,
    registered: registered,
    mine: mine,
    price: price,
    streamUrl: streamUrl,
  );
}

class _FakeLive implements LiveRepository {
  _FakeLive(this.current, {this.failLoads = 0});

  LiveSession current;
  List<LiveQuestion> questions = [];
  int failLoads;
  int? refuseWith;
  final List<String> calls = [];

  LiveDetail get _detail => LiveDetail(session: current, questions: questions);

  Future<LiveDetail> _apply(String call, LiveSession Function() next) async {
    calls.add(call);
    final status = refuseWith;
    if (status != null) throw LiveException(status);
    current = next();
    return _detail;
  }

  LiveSession _copy({String? status, bool? registered, String? streamUrl}) {
    final s = current;
    return LiveSession(
      id: s.id,
      title: s.title,
      instructor: s.instructor,
      scheduledAt: s.scheduledAt,
      durationMinutes: s.durationMinutes,
      status: status ?? s.status,
      registered: registered ?? s.registered,
      mine: s.mine,
      price: s.price,
      streamUrl: streamUrl ?? s.streamUrl,
    );
  }

  @override
  bool get bundledOnly => false;

  @override
  Future<List<LiveSession>> sessions({bool past = false}) async {
    calls.add('list:$past');
    if (failLoads > 0) {
      failLoads--;
      throw const LiveException(0);
    }
    return past ? const [] : [current];
  }

  @override
  Future<LiveDetail> detail(int id) async => _detail;

  @override
  Future<LiveDetail> register(int id, {required bool on}) {
    return _apply('register:$on', () => _copy(registered: on));
  }

  @override
  Future<LiveDetail> ask(int id, String question) {
    return _apply('ask:$question', () {
      questions = [
        ...questions,
        LiveQuestion(id: 9, question: question, author: 'ฉัน', mine: true),
      ];
      return current;
    });
  }

  @override
  Future<LiveDetail> vote(int questionId, {required bool on}) {
    return _apply('vote:$questionId:$on', () => current);
  }

  @override
  Future<List<LiveSession>> mine() async => [current];

  @override
  Future<LiveDetail> schedule({
    required String title,
    required DateTime at,
    required int minutes,
  }) {
    return _apply('schedule:$title:$minutes', () => current);
  }

  @override
  Future<LiveDetail> changeStatus(
    int id,
    String status, {
    String streamUrl = '',
    String replayUrl = '',
  }) {
    return _apply(
      'status:$status:$streamUrl',
      () => _copy(status: status, streamUrl: streamUrl),
    );
  }

  @override
  Future<LiveDetail> answer(int questionId) {
    return _apply('answer:$questionId', () => current);
  }
}

Widget _app(String initial) => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(path: '/live', builder: (_, __) => const LiveListScreen()),
          GoRoute(
            path: '/live/:id',
            builder: (_, s) =>
                LiveDetailScreen(sessionId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/instructor/go-live',
            builder: (_, __) => const InstructorLiveScreen(),
          ),
        ],
      ),
    );

Future<void> _pump(WidgetTester t, _FakeLive repo, String initial) async {
  useViewport(t, mobileSize);
  AppDependencies.liveRepository = repo;
  await t.pumpWidget(_app(initial));
  await t.pumpAndSettle();
}

void main() {
  tearDown(AppDependencies.reset);

  test('ApiLiveRepository maps sessions, detail and refusals', () async {
    final adapter = _FakeAdapter(200);
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
      ..httpClientAdapter = adapter;
    final repo = ApiLiveRepository(
      RestClient(tokenStore: MemoryTokenStore(), dio: dio),
    );

    final list = await repo.sessions(past: true);
    expect(list.single.attendees, 3);
    expect(list.single.registered, isTrue);
    expect(list.single.durationMinutes, 45);
    expect(adapter.requests.last.queryParameters['scope'], 'past');

    final detail = await repo.register(4, on: true);
    expect(detail.session.streamUrl, 'https://meet.example/go');
    expect(detail.questions.single.upvotes, 2);
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.path, '/live/4/register');

    adapter.status = 409;
    await expectLater(
      repo.changeStatus(4, 'ended'),
      throwsA(isA<LiveException>().having((e) => e.status, 'status', 409)),
    );
    expect(adapter.requests.last.method, 'PATCH');
    expect(adapter.requests.last.data, {
      'status': 'ended',
      'stream_url': '',
      'replay_url': '',
    });
  });

  testWidgets('list shows sessions, switches to past and opens one', (t) async {
    final repo = _FakeLive(_session());
    await _pump(t, repo, '/live');
    expect(find.text('Go concurrency'), findsOneWidget);
    expect(find.textContaining('1 ธ.ค. 2026 · 19:30'), findsOneWidget);

    await t.tap(find.text('ย้อนหลัง'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('list:true'));
    expect(find.text('ยังไม่มีไลฟ์ย้อนหลัง'), findsOneWidget);
  });

  testWidgets('list error has a working retry', (t) async {
    await _pump(t, _FakeLive(_session(), failLoads: 1), '/live');
    expect(find.text('โหลดรายการไลฟ์ไม่สำเร็จ'), findsOneWidget);
    await t.tap(find.text('ลองใหม่'));
    await t.pumpAndSettle();
    expect(find.text('Go concurrency'), findsOneWidget);
  });

  testWidgets('learner registers, then can ask a question', (t) async {
    final repo = _FakeLive(_session());
    await _pump(t, repo, '/live/1');
    expect(find.byType(TextField), findsNothing, reason: 'ask after register');

    await t.tap(find.text('ลงทะเบียนเข้าร่วม'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('register:true'));
    expect(find.text('ยกเลิกการลงทะเบียน'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'channel หรือ mutex?');
    await t.tap(find.byTooltip('ส่งคำถาม'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('ask:channel หรือ mutex?'));
    expect(find.text('channel หรือ mutex?'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('vote-9')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('vote:9:true'));
  });

  testWidgets('a refusal is explained in Thai', (t) async {
    final repo = _FakeLive(_session())..refuseWith = 409;
    await _pump(t, repo, '/live/1');
    await t.tap(find.text('ลงทะเบียนเข้าร่วม'));
    await t.pumpAndSettle();
    expect(
      find.text('ทำรายการนี้ไม่ได้ในสถานะปัจจุบันของไลฟ์'),
      findsOneWidget,
    );
  });

  testWidgets('paid sessions explain they cannot be joined yet', (t) async {
    await _pump(t, _FakeLive(_session(price: 299)), '/live/1');
    expect(find.text('ไลฟ์แบบชำระเงินยังลงทะเบียนในแอปไม่ได้'), findsOneWidget);
    expect(find.text('ลงทะเบียนเข้าร่วม'), findsNothing);
  });

  testWidgets('registered learners see the stream link', (t) async {
    final s = _session(
      status: 'live',
      registered: true,
      streamUrl: 'https://meet.example/go',
    );
    await _pump(t, _FakeLive(s), '/live/1');
    expect(find.text('https://meet.example/go'), findsOneWidget);
    expect(find.byTooltip('คัดลอกลิงก์'), findsOneWidget);
  });

  testWidgets('the instructor starts the session with a link', (t) async {
    final repo = _FakeLive(_session(mine: true));
    await _pump(t, repo, '/live/1');
    await t.tap(find.text('เริ่มถ่ายทอดสด'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'https://meet.example/x');
    await t.tap(find.text('ยืนยัน'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('status:live:https://meet.example/x'));
    expect(find.text('จบการถ่ายทอด'), findsOneWidget);
  });

  testWidgets('instructor page lists sessions and validates scheduling',
      (t) async {
    final repo = _FakeLive(_session(mine: true));
    await _pump(t, repo, '/instructor/go-live');
    expect(find.text('Go concurrency'), findsOneWidget);

    await t.tap(find.text('ตั้งเวลาไลฟ์'));
    await t.pumpAndSettle();
    await t.tap(find.text('บันทึก'));
    await t.pumpAndSettle();
    expect(find.text('กรอกชื่อไลฟ์'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'Flutter Q&A');
    await t.tap(find.text('บันทึก'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('schedule:Flutter Q&A:60'));
    expect(find.byType(AlertDialog), findsNothing);
  });
}
