import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/rest_client.dart';
import '../../profile/presentation/profile_sample_data.dart';
import '../../wallet/data/wallet_repository.dart' show thaiDate;

class CertificateEntry {
  const CertificateEntry({
    required this.course,
    required this.issued,
    required this.code,
    this.id,
  });

  factory CertificateEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['issued_at'] as String? ?? '';
    final issued = DateTime.tryParse(raw);
    return CertificateEntry(
      id: (json['id'] as num?)?.toInt(),
      course: json['course_name'] as String? ?? '',
      issued: issued == null ? raw : thaiDate(issued),
      code: json['certificate_code'] as String? ?? '',
    );
  }

  /// Server id; null for the bundled demo, which has no PDF to download.
  final int? id;
  final String course;
  final String issued;
  final String code;
}

abstract class CertificatesRepository {
  bool get bundledOnly;

  /// Throws when the server cannot be reached so the screen can retry.
  Future<List<CertificateEntry>> list();

  /// The certificate PDF, or null when it could not be fetched.
  Future<Uint8List?> downloadPdf(int id);
}

class ApiCertificatesRepository implements CertificatesRepository {
  ApiCertificatesRepository(this._client);

  final RestClient _client;

  @override
  bool get bundledOnly => false;

  @override
  Future<List<CertificateEntry>> list() async {
    final res = await _client.dio.get<List<dynamic>>('/certificates');
    return [
      for (final raw in res.data ?? const <dynamic>[])
        if (raw is Map<String, dynamic>) CertificateEntry.fromJson(raw),
    ];
  }

  @override
  Future<Uint8List?> downloadPdf(int id) async {
    try {
      final res = await _client.dio.get<List<int>>(
        '/certificates/$id/download',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException catch (e) {
      debugPrint('certificate download failed: ${e.response?.statusCode}');
      return null;
    }
  }
}

/// Offline stand-in (`USE_MOCK_AUTH`, tests): the mockup's demo list.
class OfflineCertificatesRepository implements CertificatesRepository {
  const OfflineCertificatesRepository();

  @override
  bool get bundledOnly => true;

  @override
  Future<List<CertificateEntry>> list() async => bundledCertificates();

  @override
  Future<Uint8List?> downloadPdf(int id) async => null;
}

List<CertificateEntry> bundledCertificates() => [
      for (final c in ProfileSampleData.certificates)
        CertificateEntry(course: c.course, issued: c.issued, code: c.code),
    ];
