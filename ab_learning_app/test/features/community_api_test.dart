import 'dart:typed_data';

import 'package:ab_learning_app/core/di/app_dependencies.dart';
import 'package:ab_learning_app/core/network/rest_client.dart';
import 'package:ab_learning_app/core/network/token_store.dart';
import 'package:ab_learning_app/features/community/data/community_repository.dart';
import 'package:ab_learning_app/features/community/presentation/community_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_helpers.dart';

class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final String body;
    if (options.path.endsWith('/comments')) {
      body = '{"items":[{"id":1,"author":"A.","content":"hi","mine":true}]}';
    } else if (options.method == 'GET') {
      body = '{"items":[{"id":5,"author":"B.","content":"post",'
          '"like_count":2,"comment_count":1,"liked_by_me":true}]}';
    } else {
      body = '{"id":5,"author":"B.","content":"post","like_count":3}';
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeCommunity implements CommunityRepository {
  _FakeCommunity({this.failLoads = 0});

  int failLoads;
  final List<String> calls = [];
  final List<FeedComment> thread = [];
  List<FeedPost> posts = [
    const FeedPost(
      id: 1,
      author: 'Mina S.',
      content: 'สวัสดีทุกคน',
      likes: 1,
      comments: 0,
    ),
    const FeedPost(
      id: 2,
      author: 'ฉัน',
      content: 'โพสต์ของฉัน',
      likes: 0,
      comments: 0,
      mine: true,
    ),
  ];

  @override
  bool get bundledOnly => false;

  @override
  Future<List<FeedPost>> feed() async {
    if (failLoads > 0) {
      failLoads--;
      throw Exception('offline');
    }
    return posts;
  }

  @override
  Future<FeedPost?> create(String content) async {
    calls.add('create:$content');
    return FeedPost(
      id: 9,
      author: 'ฉัน',
      content: content,
      likes: 0,
      comments: 0,
      mine: true,
    );
  }

  @override
  Future<FeedPost?> setLike(int postId, {required bool liked}) async {
    calls.add('like:$postId:$liked');
    final p = posts.firstWhere((x) => x.id == postId);
    return FeedPost(
      id: p.id,
      author: p.author,
      content: p.content,
      likes: p.likes + (liked ? 1 : -1),
      comments: p.comments,
      likedByMe: liked,
      mine: p.mine,
    );
  }

  @override
  Future<bool> delete(int postId) async {
    calls.add('delete:$postId');
    return true;
  }

  @override
  Future<List<FeedComment>> comments(int postId) async => List.of(thread);

  @override
  Future<List<FeedComment>?> addComment(int postId, String content) async {
    calls.add('comment:$postId:$content');
    thread.add(FeedComment(author: 'ฉัน', content: content, mine: true));
    return List.of(thread);
  }
}

Future<void> _pump(WidgetTester t, CommunityRepository repo) async {
  useViewport(t, mobileSize);
  AppDependencies.communityRepository = repo;
  await t.pumpWidget(const MaterialApp(home: CommunityScreen()));
  await t.pumpAndSettle();
}

void main() {
  tearDown(AppDependencies.reset);

  test('ApiCommunityRepository maps feed, likes and comments', () async {
    final adapter = _FakeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
      ..httpClientAdapter = adapter;
    final repo = ApiCommunityRepository(
      RestClient(tokenStore: MemoryTokenStore(), dio: dio),
    );

    final feed = await repo.feed();
    expect(feed.single.likes, 2);
    expect(feed.single.likedByMe, isTrue);

    final liked = await repo.setLike(5, liked: true);
    expect(liked?.likes, 3);
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.path, '/community/posts/5/like');

    await repo.setLike(5, liked: false);
    expect(adapter.requests.last.method, 'DELETE');

    final thread = await repo.comments(5);
    expect(thread.single.mine, isTrue);
  });

  testWidgets('publishes a post at the top of the feed', (t) async {
    final repo = _FakeCommunity();
    await _pump(t, repo);
    await t.enterText(find.byType(TextField), '  แชร์โน้ตใหม่  ');
    await t.tap(find.text('โพสต์'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('create:แชร์โน้ตใหม่'));
    expect(find.text('แชร์โน้ตใหม่'), findsOneWidget);
  });

  testWidgets('like toggles and shows the server count', (t) async {
    final repo = _FakeCommunity();
    await _pump(t, repo);
    expect(find.text('♡ 1'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('like-1')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('like:1:true'));
    expect(find.text('♥ 2'), findsOneWidget);
  });

  testWidgets('only my post has a delete button, and it asks first',
      (t) async {
    final repo = _FakeCommunity();
    await _pump(t, repo);
    expect(find.byTooltip('ลบโพสต์'), findsOneWidget);
    await t.tap(find.byTooltip('ลบโพสต์'));
    await t.pumpAndSettle();
    await t.tap(find.text('ลบ'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('delete:2'));
    expect(find.text('โพสต์ของฉัน'), findsNothing);
  });

  testWidgets('comments sheet adds a comment and updates the count',
      (t) async {
    final repo = _FakeCommunity();
    await _pump(t, repo);
    await t.tap(find.byKey(const ValueKey('comments-1')));
    await t.pumpAndSettle();
    expect(find.text('ยังไม่มีความคิดเห็น'), findsOneWidget);

    await t.enterText(find.byType(TextField).last, 'ยินดีที่ได้รู้จัก');
    await t.tap(find.byTooltip('ส่ง'));
    await t.pumpAndSettle();
    expect(repo.calls, contains('comment:1:ยินดีที่ได้รู้จัก'));
    expect(find.textContaining('ยินดีที่ได้รู้จัก'), findsOneWidget);

    await t.tapAt(const Offset(10, 10)); // tap the barrier to close
    await t.pumpAndSettle();
    expect(find.text('💬 1'), findsOneWidget);
  });

  testWidgets('error state has a working retry', (t) async {
    await _pump(t, _FakeCommunity(failLoads: 1));
    expect(find.text('โหลดโพสต์ไม่สำเร็จ'), findsOneWidget);
    await t.tap(find.text('ลองใหม่'));
    await t.pumpAndSettle();
    expect(find.text('สวัสดีทุกคน'), findsOneWidget);
  });

  testWidgets('offline demo keeps the read-only mockup feed', (t) async {
    await _pump(t, const OfflineCommunityRepository());
    expect(find.text('♥ 12   💬 4'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
