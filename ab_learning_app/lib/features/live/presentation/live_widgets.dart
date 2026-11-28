import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_card.dart';
import '../data/live_repository.dart';

/// Thai message for a refused or failed live request.
String liveErrorText(Object error) {
  final status = error is LiveException ? error.status : 0;
  switch (status) {
    case 403:
      return 'ต้องลงทะเบียนเข้าร่วมก่อน หรือไม่มีสิทธิ์ทำรายการนี้';
    case 404:
      return 'ไม่พบไลฟ์นี้';
    case 409:
      return 'ทำรายการนี้ไม่ได้ในสถานะปัจจุบันของไลฟ์';
    case 429:
      return 'ส่งถี่เกินไป รอสักครู่แล้วลองใหม่';
    case 400:
      return 'ข้อมูลไม่ถูกต้อง';
    default:
      return 'ทำรายการไม่สำเร็จ ลองอีกครั้ง';
  }
}

class LiveSessionCard extends StatelessWidget {
  const LiveSessionCard({required this.session, this.onTap, super.key});

  final LiveSession session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final live = s.status == 'live';
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppGradients.live,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.live_tv_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  style: AppTypography.base(13.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.instructor} · ${s.when}',
                  style: AppTypography.base(
                    11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.statusLabel} · ผู้ลงทะเบียน ${s.attendees}'
                  '${s.registered ? ' · ลงทะเบียนแล้ว' : ''}',
                  style: AppTypography.base(
                    11,
                    weight: FontWeight.w600,
                    color: live ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

/// A link the learner can select or copy (no in-app browser is wired yet).
class LiveLink extends StatelessWidget {
  const LiveLink({required this.label, required this.url, super.key});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.base(12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                SelectableText(url, style: AppTypography.base(12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'คัดลอกลิงก์',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('คัดลอกลิงก์แล้ว')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class LiveStateMessage extends StatelessWidget {
  const LiveStateMessage({required this.text, this.onRetry, super.key});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.base(13, color: AppColors.textSecondary),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ],
      ),
    );
  }
}
