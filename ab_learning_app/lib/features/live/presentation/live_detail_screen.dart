import 'package:flutter/material.dart';

import '../../../core/di/app_dependencies.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/hifi_button.dart';
import '../../../core/widgets/sub_page_scaffold.dart';
import '../data/live_repository.dart';
import 'live_widgets.dart';

/// One live class. Learners register, ask and upvote questions; the
/// session's instructor also starts, ends or cancels it and marks
/// questions answered.
class LiveDetailScreen extends StatefulWidget {
  const LiveDetailScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  State<LiveDetailScreen> createState() => _LiveDetailScreenState();
}

class _LiveDetailScreenState extends State<LiveDetailScreen> {
  final _question = TextEditingController();
  LiveDetail? _detail;
  bool _failed = false;
  bool _busy = false;

  LiveRepository get _repo => AppDependencies.liveRepository;
  int get _id => int.tryParse(widget.sessionId) ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final detail = await _repo.detail(_id);
      if (mounted) setState(() => _detail = detail);
    } on Object catch (e) {
      debugPrint('live detail failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Runs one action, shows the result, and reports a failure in Thai.
  Future<bool> _run(Future<LiveDetail> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final detail = await action();
      if (!mounted) return false;
      setState(() {
        _detail = detail;
        _busy = false;
      });
      return true;
    } on Object catch (e) {
      if (!mounted) return false;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(liveErrorText(e))),
      );
      return false;
    }
  }

  Future<void> _ask() async {
    final text = _question.text.trim();
    if (text.isEmpty) return;
    if (await _run(() => _repo.ask(_id, text))) _question.clear();
  }

  /// The dialog's controller is left to the garbage collector: disposing it
  /// when the dialog pops would break the closing animation.
  Future<String?> _askLink(String title, String hint) {
    final input = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(input.text.trim()),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  Future<void> _goLive() async {
    final link = await _askLink('เริ่มถ่ายทอดสด', 'ลิงก์ห้องไลฟ์ https://...');
    if (link == null) return;
    await _run(() => _repo.changeStatus(_id, 'live', streamUrl: link));
  }

  Future<void> _end() async {
    final link = await _askLink('จบการถ่ายทอด', 'ลิงก์ดูย้อนหลัง (ไม่บังคับ)');
    if (link == null) return;
    await _run(() => _repo.changeStatus(_id, 'ended', replayUrl: link));
  }

  Future<void> _register(bool on) async {
    await _run(() => _repo.register(_id, on: on));
  }

  Future<void> _cancel() async {
    await _run(() => _repo.changeStatus(_id, 'cancelled'));
  }

  Future<void> _vote(LiveQuestion q) async {
    await _run(() => _repo.vote(q.id, on: !q.votedByMe));
  }

  Future<void> _answer(LiveQuestion q) async {
    await _run(() => _repo.answer(q.id));
  }

  Widget _placeholder() {
    if (_failed) {
      return LiveStateMessage(text: 'โหลดไลฟ์ไม่สำเร็จ', onRetry: _load);
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  List<Widget> _actions(LiveSession s) {
    if (s.mine) {
      if (s.status == 'upcoming') {
        return [
          AppButton.primary(
            label: 'เริ่มถ่ายทอดสด',
            onPressed: _busy ? null : _goLive,
            expand: true,
          ),
          const SizedBox(height: 8),
          AppButton.secondary(
            label: 'ยกเลิกไลฟ์',
            onPressed: _busy ? null : _cancel,
            expand: true,
          ),
        ];
      }
      if (s.status == 'live') {
        return [
          AppButton.primary(
            label: 'จบการถ่ายทอด',
            onPressed: _busy ? null : _end,
            expand: true,
          ),
        ];
      }
      return const [];
    }
    if (!s.isOpen) return const [];
    if (s.price > 0 && !s.registered) {
      return [
        Text(
          'ไลฟ์แบบชำระเงินยังลงทะเบียนในแอปไม่ได้',
          style: AppTypography.base(12, color: AppColors.textSecondary),
        ),
      ];
    }
    return [
      if (s.registered)
        AppButton.secondary(
          label: 'ยกเลิกการลงทะเบียน',
          onPressed: _busy ? null : () => _register(false),
          expand: true,
        )
      else
        AppButton.primary(
          label: 'ลงทะเบียนเข้าร่วม',
          onPressed: _busy ? null : () => _register(true),
          expand: true,
        ),
    ];
  }

  Widget _questionTile(LiveSession s, LiveQuestion q) {
    final canVote = (s.registered || s.mine) && !q.answered;
    return AppCard(
      child: Row(
        children: [
          Column(
            children: [
              IconButton(
                key: ValueKey('vote-${q.id}'),
                tooltip: q.votedByMe ? 'ยกเลิกโหวต' : 'โหวตคำถามนี้',
                icon: Icon(
                  q.votedByMe ? Icons.thumb_up : Icons.thumb_up_outlined,
                  size: 18,
                  color: q.votedByMe ? AppColors.primary : null,
                ),
                onPressed: canVote && !_busy ? () => _vote(q) : null,
              ),
              Text('${q.upvotes}', style: AppTypography.base(11)),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.question, style: AppTypography.base(13)),
                const SizedBox(height: 2),
                Text(
                  q.answered ? '${q.author} · ตอบแล้ว' : q.author,
                  style: AppTypography.base(
                    11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (s.mine && !q.answered)
            TextButton(
              onPressed: _busy ? null : () => _answer(q),
              child: const Text('ตอบแล้ว'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final s = detail?.session;
    return SubPageScaffold(
      title: s?.title ?? 'Live',
      fallbackRoute: '/live',
      children: [
        if (detail == null || s == null)
          _placeholder()
        else ...[
          LiveSessionCard(session: s),
          const SizedBox(height: 12),
          ..._actions(s),
          if (s.streamUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            LiveLink(label: 'ลิงก์ห้องไลฟ์', url: s.streamUrl),
          ],
          if (s.replayUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            LiveLink(label: 'ดูย้อนหลัง', url: s.replayUrl),
          ],
          const SectionLabel('คำถามจากผู้เรียน'),
          if ((s.registered || s.mine) && s.isOpen)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _question,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'ถามผู้สอน...',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'ส่งคำถาม',
                  icon: const Icon(Icons.send),
                  onPressed: _busy ? null : _ask,
                ),
              ],
            ),
          if (detail.questions.isEmpty)
            const LiveStateMessage(text: 'ยังไม่มีคำถาม')
          else
            for (final q in detail.questions) ...[
              _questionTile(s, q),
              const SizedBox(height: 8),
            ],
        ],
      ],
    );
  }
}
