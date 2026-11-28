import 'dart:typed_data';

import 'package:ab_learning_app/core/di/app_dependencies.dart';
import 'package:ab_learning_app/core/network/rest_client.dart';
import 'package:ab_learning_app/core/network/token_store.dart';
import 'package:ab_learning_app/data/mock/models.dart';
import 'package:ab_learning_app/features/catalog/data/catalog_models.dart';
import 'package:ab_learning_app/features/catalog/data/catalog_repository.dart';
import 'package:ab_learning_app/features/home/models/home_feed.dart';
import 'package:ab_learning_app/features/quiz/data/quiz_repository.dart';
import 'package:ab_learning_app/features/quiz/presentation/quiz_result_screen.dart';
import 'package:ab_learning_app/features/quiz/presentation/quiz_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/test_helpers.dart';

const _quizJson = <String, dynamic>{
  'id': 9,
  'title': 'Section Quiz',
  'questions': [
    {
      'id': 101,
      'question': 'Q1',
      'choices': [
        {'id': 'a', 'text': 'A1'},
        {'id': 'b', 'text': 'B1'},
      ],
    },
    {
      'id': 102,
      'question': 'Q2',
      'choices': [
        {'id': 'a', 'text': 'A2'},
        {'id': 'b', 'text': 'B2'},
      ],
    },
  ],
};

const _gradedJson = <String, dynamic>{
  'score': 1,
  'total': 2,
  'passed': false,
  'skill_breakdown': {'Layout': 50},
  'results': [
    {'question_id': 101, 'correct_choice': 'b'},
    {'question_id': 102, 'correct_choice': 'a'},
  ],
};

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
    return ResponseBody.fromString(
      '{"score":2,"total":2,"passed":true,"results":[]}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Online catalog: only `bundledOnly` matters to the quiz screen.
class _OnlineCatalog implements CatalogRepository {
  @override
  bool get bundledOnly => false;

  @override
  Future<HomeFeed?> homeFeed() async => null;

  @override
  Future<CatalogCourse?> course(String id) async => null;

  @override
  Future<List<CatalogSection>?> curriculum(String courseId) async => null;

  @override
  Future<LessonDetail?> lesson(String id) async => null;

  @override
  Future<bool> saveProgress(
    String lessonId, {
    required int watchedSeconds,
    required String status,
  }) async {
    return false;
  }
}

class _FakeQuiz implements QuizRepository {
  _FakeQuiz({this.loadError, this.submitError});

  QuizLoadError? loadError;
  QuizSubmitError? submitError;
  List<int?>? submitted;

  @override
  Future<LessonQuiz> forLesson(int lessonId) async {
    final error = loadError;
    if (error != null) {
      loadError = null;
      throw QuizException(load: error);
    }
    return LessonQuiz.fromJson(_quizJson);
  }

  @override
  Future<GradedQuiz> submit(LessonQuiz quiz, List<int?> selected) async {
    submitted = List.of(selected);
    final error = submitError;
    if (error != null) throw QuizException(submit: error);
    return gradeFromJson(quiz, selected, _gradedJson);
  }
}

Widget _app() => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/quiz/77',
        routes: [
          GoRoute(
            path: '/quiz/:id',
            builder: (_, s) => QuizScreen(lessonId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/quiz-result',
            builder: (_, s) {
              final extra = s.extra! as Map<String, dynamic>;
              return QuizResultScreen(
                result: extra['result'] as QuizAttemptResult,
                questions: extra['questions'] as List<QuizQuestion>,
                lessonId: extra['lessonId'] as String,
              );
            },
          ),
        ],
      ),
    );

Future<void> _pump(WidgetTester t, _FakeQuiz quiz) async {
  useViewport(t, mobileSize);
  AppDependencies.catalogRepository = _OnlineCatalog();
  AppDependencies.quizRepository = quiz;
  await t.pumpWidget(_app());
  await t.pumpAndSettle();
}

void main() {
  tearDown(AppDependencies.reset);

  test('LessonQuiz.fromJson keeps choice ids and hides answers', () {
    final quiz = LessonQuiz.fromJson(_quizJson);
    expect(quiz.id, 9);
    expect(quiz.questionIds, [101, 102]);
    expect(quiz.choiceIds.first, ['a', 'b']);
    expect(quiz.questions.first.options, ['A1', 'B1']);
    expect(quiz.questions.every((q) => q.correctIndex == -1), isTrue);
  });

  test('gradeFromJson fills answers, server pass mark and skills', () {
    final quiz = LessonQuiz.fromJson(_quizJson);
    final graded = gradeFromJson(quiz, [1, 1], _gradedJson);
    expect(graded.questions.map((q) => q.correctIndex), [1, 0]);
    expect(graded.result.correctCount, 1);
    expect(graded.result.isPass, isFalse);
    expect(graded.result.skills!.single.percent, 0.5);
  });

  test('ApiQuizRepository sends choice ids and maps refusals', () async {
    final adapter = _FakeAdapter(200);
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
      ..httpClientAdapter = adapter;
    final repo = ApiQuizRepository(
      RestClient(tokenStore: MemoryTokenStore(), dio: dio),
    );
    final quiz = LessonQuiz.fromJson(_quizJson);

    final graded = await repo.submit(quiz, [1, null]);
    expect(graded.result.isPass, isTrue);
    expect(adapter.requests.last.path, '/quizzes/9/submit');
    expect(adapter.requests.last.data, {
      'answers': {'101': 'b'},
    });

    adapter.status = 403;
    await expectLater(
      repo.submit(quiz, [0, 0]),
      throwsA(
        isA<QuizException>().having(
          (e) => e.submit,
          'submit',
          QuizSubmitError.notEnrolled,
        ),
      ),
    );

    adapter.status = 404;
    await expectLater(
      repo.forLesson(77),
      throwsA(
        isA<QuizException>().having(
          (e) => e.load,
          'load',
          QuizLoadError.notFound,
        ),
      ),
    );
    expect(adapter.requests.last.path, '/lessons/77/quiz');
  });

  testWidgets('answers a server quiz and shows the graded result', (t) async {
    final quiz = _FakeQuiz();
    await _pump(t, quiz);

    expect(find.text('Section Quiz'), findsOneWidget);
    await t.tap(find.text('B1'));
    await t.pump();
    await t.tap(find.text('ถัดไป'));
    await t.pumpAndSettle();
    await t.tap(find.text('B2'));
    await t.pump();
    await t.tap(find.text('ส่งคำตอบ'));
    await t.pumpAndSettle();

    expect(quiz.submitted, [1, 1]);
    expect(find.byType(QuizResultScreen), findsOneWidget);
    expect(find.text('ตอบถูก 1/2 ข้อ'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Layout'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Layout'), findsOneWidget);
  });

  testWidgets('explains a lesson without a quiz', (t) async {
    await _pump(t, _FakeQuiz(loadError: QuizLoadError.notFound));
    expect(find.text('บทเรียนนี้ยังไม่มีแบบทดสอบ'), findsOneWidget);
  });

  testWidgets('load failure has a working retry', (t) async {
    await _pump(t, _FakeQuiz(loadError: QuizLoadError.failed));
    expect(find.text('โหลดแบบทดสอบไม่สำเร็จ'), findsOneWidget);
    await t.tap(find.text('ลองใหม่'));
    await t.pumpAndSettle();
    expect(find.text('Q1'), findsOneWidget);
  });

  testWidgets('tells a non-enrolled learner why submit failed', (t) async {
    await _pump(t, _FakeQuiz(submitError: QuizSubmitError.notEnrolled));
    await t.tap(find.text('B1'));
    await t.pump();
    await t.tap(find.text('ถัดไป'));
    await t.pumpAndSettle();
    await t.tap(find.text('A2'));
    await t.pump();
    await t.tap(find.text('ส่งคำตอบ'));
    await t.pumpAndSettle();

    expect(
      find.text('ทำแบบทดสอบได้เฉพาะผู้ที่ลงทะเบียนคอร์สนี้'),
      findsOneWidget,
    );
    expect(find.byType(QuizScreen), findsOneWidget);
  });
}
