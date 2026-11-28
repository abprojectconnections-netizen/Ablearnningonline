import 'dart:typed_data';

import 'package:ab_learning_app/core/di/app_dependencies.dart';
import 'package:ab_learning_app/core/network/rest_client.dart';
import 'package:ab_learning_app/core/network/token_store.dart';
import 'package:ab_learning_app/features/certificates/data/certificates_repository.dart';
import 'package:ab_learning_app/features/profile/presentation/certificates_screen.dart';
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
    if (options.path.endsWith('/download')) {
      return ResponseBody.fromBytes(
        [37, 80, 68, 70],
        200,
        headers: {
          Headers.contentTypeHeader: ['application/pdf'],
        },
      );
    }
    return ResponseBody.fromString(
      '[{"id":3,"certificate_code":"AB-1","course_name":"Go",'
      '"issued_at":"2026-11-20 10:00:00"}]',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeCertificates implements CertificatesRepository {
  _FakeCertificates(this.items, {this.failLoads = 0, this.pdf});

  List<CertificateEntry> items;
  int failLoads;
  Uint8List? pdf;
  final List<int> downloads = [];

  @override
  bool get bundledOnly => false;

  @override
  Future<List<CertificateEntry>> list() async {
    if (failLoads > 0) {
      failLoads--;
      throw Exception('offline');
    }
    return items;
  }

  @override
  Future<Uint8List?> downloadPdf(int id) async {
    downloads.add(id);
    return pdf;
  }
}

const _one = [
  CertificateEntry(
    id: 3,
    course: 'Go Backend',
    issued: '20 พ.ย. 2026',
    code: 'AB-1',
  ),
];

Future<void> _pump(WidgetTester t) async {
  useViewport(t, mobileSize);
  await t.pumpWidget(const MaterialApp(home: CertificatesScreen()));
  await t.pumpAndSettle();
}

void main() {
  tearDown(AppDependencies.reset);

  test('ApiCertificatesRepository lists and downloads bytes', () async {
    final adapter = _FakeAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
      ..httpClientAdapter = adapter;
    final repo = ApiCertificatesRepository(
      RestClient(tokenStore: MemoryTokenStore(), dio: dio),
    );

    final items = await repo.list();
    expect(items.single.id, 3);
    expect(items.single.course, 'Go');
    expect(items.single.issued, '20 พ.ย. 2026');

    final pdf = await repo.downloadPdf(3);
    expect(pdf, [37, 80, 68, 70]);
    expect(adapter.requests.last.path, '/certificates/3/download');
  });

  testWidgets('lists server certificates with a download button', (t) async {
    AppDependencies.certificatesRepository = _FakeCertificates(_one);
    await _pump(t);
    expect(find.text('Go Backend'), findsOneWidget);
    expect(find.text('ออกเมื่อ 20 พ.ย. 2026 · AB-1'), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
  });

  testWidgets('a failed download says so', (t) async {
    final repo = _FakeCertificates(_one);
    AppDependencies.certificatesRepository = repo;
    await _pump(t);
    await t.tap(find.byIcon(Icons.download));
    await t.pumpAndSettle();
    expect(repo.downloads, [3]);
    expect(find.text('ดาวน์โหลดไม่สำเร็จ ลองอีกครั้ง'), findsOneWidget);
  });

  testWidgets('outside the browser the user is told where to download',
      (t) async {
    final pdf = Uint8List.fromList([37, 80, 68, 70]);
    AppDependencies.certificatesRepository = _FakeCertificates(_one, pdf: pdf);
    await _pump(t);
    await t.tap(find.byIcon(Icons.download));
    await t.pumpAndSettle();
    expect(find.text('ดาวน์โหลดได้จากเว็บเบราว์เซอร์'), findsOneWidget);
  });

  testWidgets('empty state', (t) async {
    AppDependencies.certificatesRepository = _FakeCertificates(const []);
    await _pump(t);
    expect(find.textContaining('ยังไม่มีใบเกียรติบัตร'), findsOneWidget);
  });

  testWidgets('error state has a working retry', (t) async {
    AppDependencies.certificatesRepository =
        _FakeCertificates(_one, failLoads: 1);
    await _pump(t);
    expect(find.text('โหลดใบเกียรติบัตรไม่สำเร็จ'), findsOneWidget);
    await t.tap(find.text('ลองใหม่'));
    await t.pumpAndSettle();
    expect(find.text('Go Backend'), findsOneWidget);
  });
}
