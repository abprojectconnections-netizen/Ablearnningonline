import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/app_dependencies.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/radius.dart';
import '../../../core/theme/typography.dart';
import '../../../data/mock/mock_repository.dart';
import '../../../data/mock/models.dart';
import '../data/quiz_repository.dart';

/// Screen 14 — Quiz. Single-select MCQ flow with a Previous/Next footer and
/// Submit on the last question.
class QuizScreen extends StatefulWidget {
  final String lessonId;

  const QuizScreen({super.key, required this.lessonId});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  /// Set for a lesson that lives on the server (numeric id, online).
  late final int? _apiLessonId = AppDependencies.catalogRepository.bundledOnly
      ? null
      : int.tryParse(widget.lessonId);

  List<QuizQuestion> _questions = MockRepository.sampleQuiz;
  late List<int?> _selected = List.filled(_questions.length, null);
  int _index = 0;
  LessonQuiz? _quiz;
  QuizLoadError? _loadError;
  bool _submitting = false;

  bool get _fromApi => _apiLessonId != null;

  QuizQuestion get _current => _questions[_index];

  @override
  void initState() {
    super.initState();
    if (_fromApi) {
      _questions = const [];
      _selected = const [];
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final quiz =
          await AppDependencies.quizRepository.forLesson(_apiLessonId!);
      if (!mounted) return;
      setState(() {
        _quiz = quiz;
        _questions = quiz.questions;
        _selected = List.filled(quiz.questions.length, null);
        _index = 0;
        if (quiz.questions.isEmpty) _loadError = QuizLoadError.notFound;
      });
    } on QuizException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.load ?? QuizLoadError.failed);
    }
  }

  Future<void> _submit() async {
    final quiz = _quiz;
    if (quiz != null) {
      await _submitToServer(quiz);
      return;
    }
    final lesson = MockRepository.lessonById(widget.lessonId);
    if (lesson != null) {
      MockRepository.completeLesson(lesson.id);
    }

    var correct = 0;
    for (var i = 0; i < _questions.length; i++) {
      if (_selected[i] == _questions[i].correctIndex) correct++;
    }

    final result = QuizAttemptResult(
      correctCount: correct,
      totalCount: _questions.length,
      selectedAnswers: List.of(_selected),
    );

    context.pushReplacement(
      '/quiz-result',
      extra: {
        'result': result,
        'questions': _questions,
        'lessonId': widget.lessonId
      },
    );
  }

  /// The server grades; correct answers only arrive with the result.
  Future<void> _submitToServer(LessonQuiz quiz) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final graded = await AppDependencies.quizRepository.submit(
        quiz,
        _selected,
      );
      if (!mounted) return;
      context.pushReplacement(
        '/quiz-result',
        extra: {
          'result': graded.result,
          'questions': graded.questions,
          'lessonId': widget.lessonId,
        },
      );
    } on QuizException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final text = e.submit == QuizSubmitError.notEnrolled
          ? 'ทำแบบทดสอบได้เฉพาะผู้ที่ลงทะเบียนคอร์สนี้'
          : 'ส่งคำตอบไม่สำเร็จ ลองอีกครั้ง';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    }
  }

  /// Loading or error screen for a server quiz; null once it is loaded.
  Widget? _apiStateView() {
    if (!_fromApi || (_quiz != null && _loadError == null)) return null;
    final Widget body;
    if (_loadError == QuizLoadError.notFound) {
      body = Text(
        'บทเรียนนี้ยังไม่มีแบบทดสอบ',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      );
    } else if (_loadError == QuizLoadError.failed) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'โหลดแบบทดสอบไม่สำเร็จ',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          TextButton(onPressed: _load, child: const Text('ลองใหม่')),
        ],
      );
    } else {
      body = const CircularProgressIndicator();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('แบบทดสอบ')),
      body: Center(child: body),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _apiStateView();
    if (state != null) return state;
    final lesson = MockRepository.lessonById(widget.lessonId);
    final title = _quiz?.title ?? lesson?.title ?? 'แบบทดสอบ';
    final isLastQuestion = _index == _questions.length - 1;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_index + 1}/${_questions.length}',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.badge),
              child: LinearProgressIndicator(
                value: (_index + 1) / _questions.length,
                minHeight: 6,
                backgroundColor: AppColors.cardBorder,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Text(_current.question, style: AppTypography.h2),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: _current.options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final selected = _selected[_index] == i;
                  return InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    onTap: () => setState(() => _selected[_index] = i),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(
                            color: selected
                                ? AppColors.primary
                                : AppColors.cardBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(_current.options[i],
                                  style: AppTypography.body)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                if (_index > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _index -= 1),
                      style: OutlinedButton.styleFrom(
                        side:
                            const BorderSide(color: AppColors.btnOutlineBorder),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.button)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('ก่อนหน้า'),
                    ),
                  ),
                if (_index > 0) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selected[_index] == null || _submitting
                        ? null
                        : () {
                            if (isLastQuestion) {
                              _submit();
                            } else {
                              setState(() => _index += 1);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.btnPrimaryBg,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.button)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      isLastQuestion ? 'ส่งคำตอบ' : 'ถัดไป',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
