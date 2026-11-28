import 'package:flutter/material.dart';

import '../../../core/di/app_dependencies.dart';
import '../../../core/download/save_file.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/sub_page_scaffold.dart';
import '../../certificates/data/certificates_repository.dart';

/// The learner's certificates from `GET /certificates`; each one downloads
/// as a PDF. The offline demo shows the mockup's list without downloads.
class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  List<CertificateEntry>? _items;
  bool _failed = false;
  int? _downloading;

  CertificatesRepository get _repo => AppDependencies.certificatesRepository;

  @override
  void initState() {
    super.initState();
    if (_repo.bundledOnly) {
      _items = bundledCertificates();
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _failed = false;
    });
    try {
      final items = await _repo.list();
      if (!mounted) return;
      setState(() => _items = items);
    } on Object catch (e) {
      debugPrint('certificates failed to load: $e');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _download(CertificateEntry c) async {
    final id = c.id;
    if (id == null || _downloading != null) return;
    setState(() => _downloading = id);
    final bytes = await _repo.downloadPdf(id);
    var saved = false;
    if (bytes != null) {
      final name = 'certificate-${c.code}.pdf';
      saved = await saveFile(name, bytes, 'application/pdf');
    }
    if (!mounted) return;
    setState(() => _downloading = null);
    final String text;
    if (saved) {
      text = 'ดาวน์โหลดใบเกียรติบัตรแล้ว';
    } else if (bytes == null) {
      text = 'ดาวน์โหลดไม่สำเร็จ ลองอีกครั้ง';
    } else {
      text = 'ดาวน์โหลดได้จากเว็บเบราว์เซอร์';
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SubPageScaffold(
      title: 'Certificates',
      children: [
        const SizedBox(height: 8),
        if (_failed)
          _Message(
            text: 'โหลดใบเกียรติบัตรไม่สำเร็จ',
            action: TextButton(onPressed: _load, child: const Text('ลองใหม่')),
          )
        else if (items == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          const _Message(
            text: 'ยังไม่มีใบเกียรติบัตร\nเรียนจบคอร์สเพื่อรับใบเกียรติบัตร',
          )
        else
          for (final c in items) ...[
            _CertificateCard(
              entry: c,
              downloading: _downloading == c.id,
              onDownload: c.id == null ? null : () => _download(c),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.base(13, color: AppColors.textSecondary),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.entry,
    required this.downloading,
    required this.onDownload,
  });

  final CertificateEntry entry;
  final bool downloading;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppGradients.warm,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.workspace_premium, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.course,
                  style: AppTypography.base(13, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'ออกเมื่อ ${entry.issued} · ${entry.code}',
                  style: AppTypography.base(
                    11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onDownload != null)
            downloading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'ดาวน์โหลด PDF',
                    icon: const Icon(Icons.download),
                    onPressed: onDownload,
                  ),
        ],
      ),
    );
  }
}
