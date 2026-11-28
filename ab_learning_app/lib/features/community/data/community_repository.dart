import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/rest_client.dart';

class FeedPost {
  const FeedPost({
    required this.id,
    required this.author,
    required this.content,
    required this.likes,
    required this.comments,
    this.likedByMe = false,
    this.mine = false,
  });

  factory FeedPost.fromJson(Map<String, dynamic> json) => FeedPost(
        id: (json['id'] as num?)?.toInt() ?? 0,
        author: json['author'] as String? ?? '',
        content: json['content'] as String? ?? '',
        likes: (json['like_count'] as num?)?.toInt() ?? 0,
        comments: (json['comment_count'] as num?)?.toInt() ?? 0,
        likedByMe: json['liked_by_me'] as bool? ?? false,
        mine: json['mine'] as bool? ?? false,
      );

  final int id;
  final String author;
  final String content;
  final int likes;
  final int comments;
  final bool likedByMe;
  final bool mine;

  FeedPost withComments(int count) => FeedPost(
        id: id,
        author: author,
        content: content,
        likes: likes,
        comments: count,
        likedByMe: likedByMe,
        mine: mine,
      );
}

class FeedComment {
  const FeedComment({
    required this.author,
    required this.content,
    this.mine = false,
  });

  factory FeedComment.fromJson(Map<String, dynamic> json) => FeedComment(
        author: json['author'] as String? ?? '',
        content: json['content'] as String? ?? '',
        mine: json['mine'] as bool? ?? false,
      );

  final String author;
  final String content;
  final bool mine;
}

List<FeedComment> _comments(Map<String, dynamic>? json) => [
      for (final raw in (json?['items'] as List<dynamic>? ?? const []))
        if (raw is Map<String, dynamic>) FeedComment.fromJson(raw),
    ];

abstract class CommunityRepository {
  bool get bundledOnly;

  /// Throws when the server cannot be reached so the screen can retry.
  Future<List<FeedPost>> feed();

  /// The new post, or null when the server refused it.
  Future<FeedPost?> create(String content);

  /// The post with its updated counter, or null on failure.
  Future<FeedPost?> setLike(int postId, {required bool liked});

  Future<bool> delete(int postId);

  /// Throws when the thread cannot be loaded.
  Future<List<FeedComment>> comments(int postId);

  /// The whole thread after adding, or null when the server refused it.
  Future<List<FeedComment>?> addComment(int postId, String content);
}

class ApiCommunityRepository implements CommunityRepository {
  ApiCommunityRepository(this._client);

  final RestClient _client;

  static const _base = '/community/posts';

  @override
  bool get bundledOnly => false;

  @override
  Future<List<FeedPost>> feed() async {
    final res = await _client.dio.get<Map<String, dynamic>>(
      _base,
      queryParameters: {'limit': 50},
    );
    return [
      for (final raw in (res.data?['items'] as List<dynamic>? ?? const []))
        if (raw is Map<String, dynamic>) FeedPost.fromJson(raw),
    ];
  }

  @override
  Future<FeedPost?> create(String content) {
    final request = _client.dio.post<Map<String, dynamic>>(
      _base,
      data: {'content': content},
    );
    return _post(request);
  }

  @override
  Future<FeedPost?> setLike(int postId, {required bool liked}) {
    final path = '$_base/$postId/like';
    final request = liked
        ? _client.dio.post<Map<String, dynamic>>(path)
        : _client.dio.delete<Map<String, dynamic>>(path);
    return _post(request);
  }

  Future<FeedPost?> _post(Future<Response<Map<String, dynamic>>> req) async {
    try {
      final res = await req;
      final data = res.data;
      return data == null ? null : FeedPost.fromJson(data);
    } on DioException catch (e) {
      debugPrint('community request failed: ${e.response?.statusCode}');
      return null;
    }
  }

  @override
  Future<bool> delete(int postId) async {
    try {
      await _client.dio.delete<Object?>('$_base/$postId');
      return true;
    } on DioException catch (e) {
      debugPrint('delete post failed: ${e.response?.statusCode}');
      return false;
    }
  }

  @override
  Future<List<FeedComment>> comments(int postId) async {
    final res = await _client.dio.get<Map<String, dynamic>>(
      '$_base/$postId/comments',
    );
    return _comments(res.data);
  }

  @override
  Future<List<FeedComment>?> addComment(int postId, String content) async {
    try {
      final res = await _client.dio.post<Map<String, dynamic>>(
        '$_base/$postId/comments',
        data: {'content': content},
      );
      return _comments(res.data);
    } on DioException catch (e) {
      debugPrint('add comment failed: ${e.response?.statusCode}');
      return null;
    }
  }
}

/// Offline stand-in (`USE_MOCK_AUTH`, tests): the mockup's read-only feed.
class OfflineCommunityRepository implements CommunityRepository {
  const OfflineCommunityRepository();

  static const samplePosts = <FeedPost>[
    FeedPost(
      id: 1,
      author: 'Nattaya P.',
      content:
          'เพิ่งเรียน Go จบบทที่ 5 ใครมีเทคนิคจัดโครงสร้างโปรเจกต์ แนะนำหน่อยครับ',
      likes: 12,
      comments: 4,
    ),
    FeedPost(
      id: 2,
      author: 'Somchai K.',
      content: 'แชร์โน้ต SQL JOIN แบบเข้าใจง่าย ใช้ตัวอย่างร้านกาแฟ',
      likes: 31,
      comments: 9,
    ),
    FeedPost(
      id: 3,
      author: 'Pim W.',
      content: 'มีใครตั้งกลุ่มติว Prompt Engineering สัปดาห์นี้บ้าง?',
      likes: 7,
      comments: 2,
    ),
  ];

  @override
  bool get bundledOnly => true;

  @override
  Future<List<FeedPost>> feed() async => samplePosts;

  @override
  Future<FeedPost?> create(String content) async => null;

  @override
  Future<FeedPost?> setLike(int postId, {required bool liked}) async => null;

  @override
  Future<bool> delete(int postId) async => false;

  @override
  Future<List<FeedComment>> comments(int postId) async => const [];

  @override
  Future<List<FeedComment>?> addComment(int postId, String content) async =>
      null;
}
