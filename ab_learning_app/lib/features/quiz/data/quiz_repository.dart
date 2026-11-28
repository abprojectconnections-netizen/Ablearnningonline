import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/rest_client.dart';
import '../../../data/mock/models.dart';

/// A quiz as served before grading: choices only, no correct answers.
class LessonQuiz {
  const LessonQuiz({
    required this.id,
    required this.title,
    required this.questionIds,
    required this.choiceIds,
    required this.questions,
  });

  factory LessonQuiz.fromJson(Map<String, dynamic> json) {
    final ids = <int>[];
    final choiceIds = <List<String>>[];
    final questions = <QuizQuestion>[];
    for (final raw in (json['questions'] as List<dynamic>? ?? const [])) {
      if (raw is! Map<String, dynamic>) continue;
      final choices = [
        for (final c in (raw['choices'] as List<dynamic>? ?? const []))
          if (c is Map<String, dynamic>) c,
      ];
      ids.add((raw['id'] as num?)?.toInt() ?? 0);
      choiceIds.add([for (final c in choices) '${c['id']}']);
      questions.add(
        QuizQuestion(
          question: raw['question'] as String? ?? '',
          options: [for (final c in choices) c['text'] as String? ?? ''],
          correctIndex: -1, // unknown until the server grades the attempt
        ),
      );
    }
    return LessonQuiz(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? 'แบบทดสอบ',
      questionIds: ids,
      choiceIds: choiceIds,
      questions: questions,
    );
  }

  final int id;
  final String title;
  final List<int> questionIds;
  final List<List<String>> choiceIds;
  final List<QuizQuestion> questions;
}

/// What the result screen needs: the score plus the questions with their
/// correct answers filled in from the server's corrections.
class GradedQuiz {
  const GradedQuiz({required this.result, required this.questions});

  final QuizAttemptResult result;
  final List<QuizQuestion> questions;
}

enum QuizLoadError { notFound, failed }

enum QuizSubmitError { notEnrolled, failed }

class QuizException implements Exception {
  const QuizException({this.load, this.submit});

  final QuizLoadError? load;
  final QuizSubmitError? submit;
}

/// Grades [selected] (option index per question) using the server's
/// `results`, matched by question id.
GradedQuiz gradeFromJson(
  LessonQuiz quiz,
  List<int?> selected,
  Map<String, dynamic> json,
) {
  final correctById = <int, String>{};
  for (final raw in (json['results'] as List<dynamic>? ?? const [])) {
    if (raw is Map<String, dynamic>) {
      final id = (raw['question_id'] as num?)?.toInt();
      if (id != null) correctById[id] = '${raw['correct_choice']}';
    }
  }
  final questions = <QuizQuestion>[
    for (var i = 0; i < quiz.questions.length; i++)
      QuizQuestion(
        question: quiz.questions[i].question,
        options: quiz.questions[i].options,
        correctIndex:
            quiz.choiceIds[i].indexOf(correctById[quiz.questionIds[i]] ?? ''),
      ),
  ];
  final breakdown = json['skill_breakdown'];
  final skills = <SkillScore>[
    if (breakdown is Map<String, dynamic>)
      for (final e in breakdown.entries)
        SkillScore(
          skill: e.key,
          percent: ((e.value as num?)?.toDouble() ?? 0) / 100,
        ),
  ];
  return GradedQuiz(
    questions: questions,
    result: QuizAttemptResult(
      correctCount: (json['score'] as num?)?.toInt() ?? 0,
      totalCount: (json['total'] as num?)?.toInt() ?? quiz.questions.length,
      selectedAnswers: List.of(selected),
      passed: json['passed'] as bool?,
      skills: skills,
    ),
  );
}

abstract class QuizRepository {
  /// Throws [QuizException] (`load`) when there is no quiz or no connection.
  Future<LessonQuiz> forLesson(int lessonId);

  /// Throws [QuizException] (`submit`) when the server refuses or fails.
  Future<GradedQuiz> submit(LessonQuiz quiz, List<int?> selected);
}

class ApiQuizRepository implements QuizRepository {
  ApiQuizRepository(this._client);

  final RestClient _client;

  @override
  Future<LessonQuiz> forLesson(int lessonId) async {
    try {
      final res = await _client.dio.get<Map<String, dynamic>>(
        '/lessons/$lessonId/quiz',
      );
      return LessonQuiz.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      debugPrint('quiz load failed: ${e.response?.statusCode ?? e.type}');
      throw QuizException(
        load: e.response?.statusCode == 404
            ? QuizLoadError.notFound
            : QuizLoadError.failed,
      );
    }
  }

  @override
  Future<GradedQuiz> submit(LessonQuiz quiz, List<int?> selected) async {
    final answers = <String, String>{
      for (var i = 0; i < quiz.questions.length; i++)
        if (selected[i] != null)
          '${quiz.questionIds[i]}': quiz.choiceIds[i][selected[i]!],
    };
    try {
      final res = await _client.dio.post<Map<String, dynamic>>(
        '/quizzes/${quiz.id}/submit',
        data: {'answers': answers},
      );
      return gradeFromJson(quiz, selected, res.data ?? const {});
    } on DioException catch (e) {
      debugPrint('quiz submit failed: ${e.response?.statusCode ?? e.type}');
      throw QuizException(
        submit: e.response?.statusCode == 403
            ? QuizSubmitError.notEnrolled
            : QuizSubmitError.failed,
      );
    }
  }
}
