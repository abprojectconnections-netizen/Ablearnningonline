import 'package:dio/dio.dart';

import '../../../core/network/rest_client.dart';
import '../../home/presentation/home_sample_data.dart';
import '../../wallet/data/wallet_repository.dart' show thaiDate;

class LiveSession {
  const LiveSession({
    required this.id,
    required this.title,
    required this.instructor,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.status,
    this.price = 0,
    this.attendees = 0,
    this.registered = false,
    this.mine = false,
    this.streamUrl = '',
    this.replayUrl = '',
  });

  factory LiveSession.fromJson(Map<String, dynamic> json) => LiveSession(
        id: (json['id'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        instructor: json['instructor'] as String? ?? '',
        scheduledAt:
            DateTime.tryParse(json['scheduled_at'] as String? ?? '')?.toLocal(),
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 60,
        status: json['status'] as String? ?? 'upcoming',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        attendees: (json['attendees'] as num?)?.toInt() ?? 0,
        registered: json['registered'] as bool? ?? false,
        mine: json['mine'] as bool? ?? false,
        streamUrl: json['stream_url'] as String? ?? '',
        replayUrl: json['replay_url'] as String? ?? '',
      );

  final int id;
  final String title;
  final String instructor;
  final DateTime? scheduledAt;
  final int durationMinutes;
  final String status;
  final double price;
  final int attendees;
  final bool registered;
  final bool mine;
  final String streamUrl;
  final String replayUrl;

  bool get isOpen => status == 'upcoming' || status == 'live';

  /// "12 ธ.ค. 2026 · 19:30 · 60 นาที"
  String get when {
    final at = scheduledAt;
    if (at == null) return '$durationMinutes นาที';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${thaiDate(at)} · $hh:$mm · $durationMinutes นาที';
  }

  String get statusLabel {
    switch (status) {
      case 'live':
        return 'กำลังถ่ายทอดสด';
      case 'ended':
        return 'จบแล้ว';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return 'กำลังจะเริ่ม';
    }
  }
}

class LiveQuestion {
  const LiveQuestion({
    required this.id,
    required this.question,
    required this.author,
    this.upvotes = 0,
    this.votedByMe = false,
    this.answered = false,
    this.mine = false,
  });

  factory LiveQuestion.fromJson(Map<String, dynamic> json) => LiveQuestion(
        id: (json['id'] as num?)?.toInt() ?? 0,
        question: json['question'] as String? ?? '',
        author: json['author'] as String? ?? '',
        upvotes: (json['upvotes'] as num?)?.toInt() ?? 0,
        votedByMe: json['voted_by_me'] as bool? ?? false,
        answered: json['answered'] as bool? ?? false,
        mine: json['mine'] as bool? ?? false,
      );

  final int id;
  final String question;
  final String author;
  final int upvotes;
  final bool votedByMe;
  final bool answered;
  final bool mine;
}

class LiveDetail {
  const LiveDetail({required this.session, required this.questions});

  factory LiveDetail.fromJson(Map<String, dynamic> json) => LiveDetail(
        session: LiveSession.fromJson(json),
        questions: [
          for (final raw in (json['questions'] as List<dynamic>? ?? const []))
            if (raw is Map<String, dynamic>) LiveQuestion.fromJson(raw),
        ],
      );

  final LiveSession session;
  final List<LiveQuestion> questions;
}

/// A refused or failed request; [status] is the HTTP status (0 = no
/// connection) so screens can explain what happened.
class LiveException implements Exception {
  const LiveException(this.status);

  final int status;
}

abstract class LiveRepository {
  bool get bundledOnly;

  Future<List<LiveSession>> sessions({bool past = false});
  Future<LiveDetail> detail(int id);
  Future<LiveDetail> register(int id, {required bool on});
  Future<LiveDetail> ask(int id, String question);
  Future<LiveDetail> vote(int questionId, {required bool on});

  // Instructor
  Future<List<LiveSession>> mine();
  Future<LiveDetail> schedule({
    required String title,
    required DateTime at,
    required int minutes,
  });
  Future<LiveDetail> changeStatus(
    int id,
    String status, {
    String streamUrl = '',
    String replayUrl = '',
  });
  Future<LiveDetail> answer(int questionId);
}

class ApiLiveRepository implements LiveRepository {
  ApiLiveRepository(this._client);

  final RestClient _client;

  Dio get _dio => _client.dio;

  @override
  bool get bundledOnly => false;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw LiveException(e.response?.statusCode ?? 0);
    }
  }

  Future<LiveDetail> _detail(Future<Response<Map<String, dynamic>>> req) {
    return _guard(() async => LiveDetail.fromJson((await req).data ?? {}));
  }

  List<LiveSession> _items(Map<String, dynamic>? json) => [
        for (final raw in (json?['items'] as List<dynamic>? ?? const []))
          if (raw is Map<String, dynamic>) LiveSession.fromJson(raw),
      ];

  @override
  Future<List<LiveSession>> sessions({bool past = false}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/live',
        queryParameters: {if (past) 'scope': 'past'},
      );
      return _items(res.data);
    });
  }

  @override
  Future<LiveDetail> detail(int id) {
    return _detail(_dio.get<Map<String, dynamic>>('/live/$id'));
  }

  @override
  Future<LiveDetail> register(int id, {required bool on}) {
    final path = '/live/$id/register';
    return _detail(
      on
          ? _dio.post<Map<String, dynamic>>(path)
          : _dio.delete<Map<String, dynamic>>(path),
    );
  }

  @override
  Future<LiveDetail> ask(int id, String question) {
    return _detail(
      _dio.post<Map<String, dynamic>>(
        '/live/$id/questions',
        data: {'question': question},
      ),
    );
  }

  @override
  Future<LiveDetail> vote(int questionId, {required bool on}) {
    final path = '/live/questions/$questionId/upvote';
    return _detail(
      on
          ? _dio.post<Map<String, dynamic>>(path)
          : _dio.delete<Map<String, dynamic>>(path),
    );
  }

  @override
  Future<List<LiveSession>> mine() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/instructor/live');
      return _items(res.data);
    });
  }

  @override
  Future<LiveDetail> schedule({
    required String title,
    required DateTime at,
    required int minutes,
  }) {
    return _detail(
      _dio.post<Map<String, dynamic>>(
        '/instructor/live',
        data: {
          'title': title,
          'scheduled_at': at.toUtc().toIso8601String(),
          'duration_minutes': minutes,
        },
      ),
    );
  }

  @override
  Future<LiveDetail> changeStatus(
    int id,
    String status, {
    String streamUrl = '',
    String replayUrl = '',
  }) {
    return _detail(
      _dio.patch<Map<String, dynamic>>(
        '/instructor/live/$id/status',
        data: {
          'status': status,
          'stream_url': streamUrl,
          'replay_url': replayUrl,
        },
      ),
    );
  }

  @override
  Future<LiveDetail> answer(int questionId) {
    return _detail(
      _dio.post<Map<String, dynamic>>(
        '/instructor/live/questions/$questionId/answered',
      ),
    );
  }
}

/// Offline stand-in (`USE_MOCK_AUTH`, tests): one read-only demo session.
class OfflineLiveRepository implements LiveRepository {
  const OfflineLiveRepository();

  static const demo = LiveSession(
    id: 1,
    title: HomeSampleData.liveTitle,
    instructor: 'AB LEARNING',
    scheduledAt: null,
    durationMinutes: 60,
    status: 'upcoming',
  );

  static const _detail = LiveDetail(session: demo, questions: []);

  @override
  bool get bundledOnly => true;

  @override
  Future<List<LiveSession>> sessions({bool past = false}) async {
    return past ? const [] : const [demo];
  }

  @override
  Future<LiveDetail> detail(int id) async => _detail;

  Never _readOnly() => throw const LiveException(0);

  @override
  Future<LiveDetail> register(int id, {required bool on}) async {
    _readOnly();
  }

  @override
  Future<LiveDetail> ask(int id, String question) async {
    _readOnly();
  }

  @override
  Future<LiveDetail> vote(int questionId, {required bool on}) async {
    _readOnly();
  }

  @override
  Future<List<LiveSession>> mine() async => const [];

  @override
  Future<LiveDetail> schedule({
    required String title,
    required DateTime at,
    required int minutes,
  }) async {
    _readOnly();
  }

  @override
  Future<LiveDetail> changeStatus(
    int id,
    String status, {
    String streamUrl = '',
    String replayUrl = '',
  }) async {
    _readOnly();
  }

  @override
  Future<LiveDetail> answer(int questionId) async {
    _readOnly();
  }
}
