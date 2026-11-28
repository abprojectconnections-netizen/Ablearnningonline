import 'package:flutter/painting.dart';

import '../../../core/format/baht.dart';
import '../../../core/network/rest_client.dart';
import '../../../core/theme/colors.dart';
import 'course_catalog_sample.dart';

const _gradients = <Gradient>[
  AppGradients.brand,
  AppGradients.accentPrimary,
  AppGradients.accentSecondary,
  AppGradients.live,
  AppGradients.warm,
];

/// One chip on Explore. A null [slug] means "all categories".
class ExploreCategory {
  const ExploreCategory({required this.label, this.slug});

  final String label;
  final String? slug;
}

/// Maps one `GET /courses` row onto the card model the hi-fi screens use.
CatalogCourse catalogCourseFromJson(Map<String, dynamic> json, int index) {
  final price = (json['price'] as num?)?.toDouble() ?? 0;
  final discount = (json['discount_price'] as num?)?.toDouble();
  final rating = (json['rating_avg'] as num?)?.toDouble() ?? 0;
  return CatalogCourse(
    id: '${(json['id'] as num?)?.toInt() ?? 0}',
    title: json['title'] as String? ?? '',
    rating: rating > 0 ? '${rating.toStringAsFixed(1)} ★' : 'ใหม่',
    price: formatBaht(discount ?? price),
    gradient: _gradients[index % _gradients.length],
  );
}

ExploreCategory categoryFromJson(Map<String, dynamic> json) {
  final th = (json['name_th'] as String? ?? '').trim();
  final en = (json['name_en'] as String? ?? '').trim();
  return ExploreCategory(
    label: th.isNotEmpty ? th : en,
    slug: json['slug'] as String?,
  );
}

abstract class ExploreRepository {
  bool get bundledOnly;

  /// Published courses, optionally narrowed by category slug and free text.
  /// Throws when the server cannot be reached.
  Future<List<CatalogCourse>> courses({String? category, String query = ''});

  /// Chips for Explore, starting with "ทั้งหมด".
  Future<List<ExploreCategory>> categories();
}

class ApiExploreRepository implements ExploreRepository {
  ApiExploreRepository(this._client);

  final RestClient _client;

  @override
  bool get bundledOnly => false;

  @override
  Future<List<CatalogCourse>> courses({
    String? category,
    String query = '',
  }) async {
    final q = query.trim();
    final res = await _client.dio.get<List<dynamic>>(
      q.isEmpty ? '/courses' : '/search',
      queryParameters: {
        'limit': 100,
        if (category != null && category.isNotEmpty) 'category': category,
        if (q.isNotEmpty) 'q': q,
      },
    );
    final rows = res.data ?? const <dynamic>[];
    return [
      for (var i = 0; i < rows.length; i++)
        if (rows[i] is Map<String, dynamic>)
          catalogCourseFromJson(rows[i] as Map<String, dynamic>, i),
    ];
  }

  @override
  Future<List<ExploreCategory>> categories() async {
    final res = await _client.dio.get<List<dynamic>>('/categories');
    return [
      const ExploreCategory(label: 'ทั้งหมด'),
      for (final raw in res.data ?? const <dynamic>[])
        if (raw is Map<String, dynamic>) categoryFromJson(raw),
    ];
  }
}

/// Offline stand-in (`USE_MOCK_AUTH`, tests): the mockup's demo catalog.
class OfflineExploreRepository implements ExploreRepository {
  const OfflineExploreRepository();

  @override
  bool get bundledOnly => true;

  @override
  Future<List<CatalogCourse>> courses({
    String? category,
    String query = '',
  }) async {
    if (query.trim().isEmpty) return CourseCatalogSample.all;
    return CourseCatalogSample.search(query);
  }

  @override
  Future<List<ExploreCategory>> categories() async {
    return [
      for (final label in CourseCatalogSample.categories)
        ExploreCategory(label: label),
    ];
  }
}
