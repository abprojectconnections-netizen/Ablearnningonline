import 'dart:typed_data';

import 'package:ab_learning_app/core/di/app_dependencies.dart';
import 'package:ab_learning_app/core/network/rest_client.dart';
import 'package:ab_learning_app/core/network/token_store.dart';
import 'package:ab_learning_app/core/theme/colors.dart';
import 'package:ab_learning_app/features/explore/data/course_catalog_sample.dart';
import 'package:ab_learning_app/features/explore/data/explore_repository.dart';
import 'package:ab_learning_app/features/explore/presentation/hifi_explore_screen.dart';
import 'package:ab_learning_app/features/explore/presentation/search_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_helpers.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final String Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      handler(options),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

CatalogCourse _course(String id, String title) => CatalogCourse(
      id: id,
      title: title,
      rating: '4.5 ★',
      price: '฿990',
      gradient: AppGradients.brand,
    );

class _FakeExplore implements ExploreRepository {
  _FakeExplore({this.failLoads = 0});

  int failLoads;
  final List<({String? category, String query})> calls = [];

  @override
  bool get bundledOnly => false;

  @override
  Future<List<CatalogCourse>> courses({
    String? category,
    String query = '',
  }) async {
    calls.add((category: category, query: query));
    if (failLoads > 0) {
      failLoads--;
      throw Exception('offline');
    }
    if (category == 'empty') return const [];
    if (query.isNotEmpty) return [_course('9', 'ผลค้นหา $query')];
    return [
      _course('1', 'คอร์สแรก'),
      _course('2', 'คอร์สที่สอง'),
      _course('3', 'คอร์สที่สาม'),
    ];
  }

  @override
  Future<List<ExploreCategory>> categories() async => const [
        ExploreCategory(label: 'ทั้งหมด'),
        ExploreCategory(label: 'โปรแกรมมิ่ง', slug: 'programming'),
        ExploreCategory(label: 'ว่าง', slug: 'empty'),
      ];
}

Future<void> _pump(WidgetTester t, Widget screen) async {
  useViewport(t, mobileSize);
  await t.pumpWidget(MaterialApp(home: screen));
  await t.pumpAndSettle();
}

void main() {
  tearDown(AppDependencies.reset);

  test('catalogCourseFromJson prefers the discount price', () {
    final row = <String, dynamic>{
      'id': 5,
      'title': 'Go',
      'price': 1990,
      'discount_price': 1490,
      'rating_avg': 4.76,
    };
    final c = catalogCourseFromJson(row, 0);
    expect(c.id, '5');
    expect(c.price, '฿1,490');
    expect(c.rating, '4.8 ★');

    final fresh = catalogCourseFromJson({'id': 6, 'price': 0}, 1);
    expect(fresh.price, 'ฟรี');
    expect(fresh.rating, 'ใหม่');
  });

  test('ApiExploreRepository uses /courses, /search and /categories', () async {
    final adapter = _FakeAdapter((o) {
      if (o.path == '/categories') {
        return '[{"id":1,"name_th":"","name_en":"Programming",'
            '"slug":"programming"}]';
      }
      return '[{"id":1,"title":"Go","price":990,"rating_avg":4.5}]';
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
      ..httpClientAdapter = adapter;
    final repo = ApiExploreRepository(
      RestClient(tokenStore: MemoryTokenStore(), dio: dio),
    );

    final cats = await repo.categories();
    expect(cats.map((c) => c.label), ['ทั้งหมด', 'Programming']);
    expect(cats.first.slug, isNull);

    await repo.courses(category: 'programming');
    expect(adapter.requests.last.path, '/courses');
    expect(adapter.requests.last.queryParameters['category'], 'programming');

    await repo.courses(query: ' go ');
    expect(adapter.requests.last.path, '/search');
    expect(adapter.requests.last.queryParameters['q'], 'go');
  });

  testWidgets('Explore lists server courses and reloads per category',
      (t) async {
    final repo = _FakeExplore();
    AppDependencies.exploreRepository = repo;
    await _pump(t, const HifiExploreScreen());

    expect(find.text('คอร์สแรก'), findsOneWidget);
    expect(find.text('คอร์สที่สาม'), findsOneWidget);
    expect(find.text('โปรแกรมมิ่ง'), findsOneWidget);

    await t.tap(find.text('โปรแกรมมิ่ง'));
    await t.pumpAndSettle();
    expect(repo.calls.last.category, 'programming');

    await t.tap(find.text('ว่าง'));
    await t.pumpAndSettle();
    expect(find.text('ยังไม่มีคอร์สในหมวดนี้'), findsOneWidget);
  });

  testWidgets('Explore error state has a working retry', (t) async {
    AppDependencies.exploreRepository = _FakeExplore(failLoads: 1);
    await _pump(t, const HifiExploreScreen());
    expect(find.text('โหลดคอร์สไม่สำเร็จ'), findsOneWidget);
    await t.tap(find.text('ลองใหม่'));
    await t.pumpAndSettle();
    expect(find.text('คอร์สแรก'), findsOneWidget);
  });

  testWidgets('Search asks the server after typing stops', (t) async {
    final repo = _FakeExplore();
    AppDependencies.exploreRepository = repo;
    await _pump(t, const SearchScreen(initialQuery: 'x'));
    final before = repo.calls.length;

    await t.enterText(find.byType(TextField), 'flutter');
    await t.pump(const Duration(milliseconds: 100));
    expect(repo.calls.length, before, reason: 'debounced, not yet sent');

    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(repo.calls.last.query, 'flutter');
    expect(find.text('ผลค้นหา flutter'), findsOneWidget);
    expect(find.text('ผลการค้นหา (1)'), findsOneWidget);
  });
}
