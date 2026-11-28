import 'package:flutter/material.dart';

import '../../../core/di/app_dependencies.dart';
import '../../../core/router/nav_targets.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_sidebar.dart';
import '../../../core/widgets/hifi_button.dart';
import '../../../core/widgets/responsive.dart';
import '../data/community_repository.dart';

/// Learners' feed from `/community/posts`: write a post, like, comment and
/// delete your own. The offline demo shows the mockup's read-only feed.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final _composer = TextEditingController();
  List<FeedPost>? _posts;
  bool _failed = false;
  bool _posting = false;

  CommunityRepository get _repo => AppDependencies.communityRepository;

  @override
  void initState() {
    super.initState();
    if (_repo.bundledOnly) {
      _posts = OfflineCommunityRepository.samplePosts;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _posts = null;
      _failed = false;
    });
    try {
      final posts = await _repo.feed();
      if (!mounted) return;
      setState(() => _posts = posts);
    } on Object catch (e) {
      debugPrint('community feed failed to load: $e');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _replace(FeedPost updated) {
    final posts = _posts;
    if (posts == null) return;
    setState(() {
      _posts = [for (final p in posts) p.id == updated.id ? updated : p];
    });
  }

  Future<void> _publish() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    final post = await _repo.create(text);
    if (!mounted) return;
    setState(() => _posting = false);
    if (post == null) {
      _toast('โพสต์ไม่สำเร็จ ลองอีกครั้ง');
      return;
    }
    _composer.clear();
    setState(() => _posts = [post, ...?_posts]);
  }

  Future<void> _toggleLike(FeedPost p) async {
    final updated = await _repo.setLike(p.id, liked: !p.likedByMe);
    if (!mounted) return;
    if (updated == null) {
      _toast('กดถูกใจไม่สำเร็จ');
      return;
    }
    _replace(updated);
  }

  Future<void> _delete(FeedPost p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบโพสต์นี้?'),
        content: const Text('ความคิดเห็นและการถูกใจของโพสต์นี้จะถูกลบด้วย'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _repo.delete(p.id);
    if (!mounted) return;
    if (!ok) {
      _toast('ลบโพสต์ไม่สำเร็จ');
      return;
    }
    setState(() => _posts = [...?_posts]..removeWhere((x) => x.id == p.id));
  }

  Future<void> _openComments(FeedPost p) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => _CommentsSheet(postId: p.id),
    );
    if (count != null && mounted) _replace(p.withComments(count));
  }

  Widget _composerCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _composer,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(
              hintText: 'แชร์ความรู้หรือถามคำถาม...',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton.primary(
              label: 'โพสต์',
              loading: _posting,
              onPressed: _posting ? null : _publish,
            ),
          ),
        ],
      ),
    );
  }

  Widget _postCard(FeedPost p) {
    final interactive = !_repo.bundledOnly;
    final meta = AppTypography.base(11, color: AppColors.textSecondary);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(initial: p.author.isEmpty ? '?' : p.author[0]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.author,
                  style: AppTypography.base(13, weight: FontWeight.w600),
                ),
              ),
              if (interactive && p.mine)
                IconButton(
                  tooltip: 'ลบโพสต์',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _delete(p),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(p.content, style: AppTypography.base(13, height: 1.5)),
          const SizedBox(height: 8),
          if (!interactive)
            Text('♥ ${p.likes}   💬 ${p.comments}', style: meta)
          else
            Row(
              children: [
                InkWell(
                  key: ValueKey('like-${p.id}'),
                  onTap: () => _toggleLike(p),
                  child: Text(
                    '${p.likedByMe ? '♥' : '♡'} ${p.likes}',
                    style: p.likedByMe
                        ? meta.copyWith(color: AppColors.primary)
                        : meta,
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  key: ValueKey('comments-${p.id}'),
                  onTap: () => _openComments(p),
                  child: Text('💬 ${p.comments}', style: meta),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _feed() {
    final posts = _posts;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('Community',
            style: AppTypography.base(18, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (!_repo.bundledOnly) ...[
          _composerCard(),
          const SizedBox(height: 12),
        ],
        if (_failed)
          Column(
            children: [
              Text(
                'โหลดโพสต์ไม่สำเร็จ',
                style: AppTypography.base(13, color: AppColors.textSecondary),
              ),
              TextButton(onPressed: _load, child: const Text('ลองใหม่')),
            ],
          )
        else if (posts == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'ยังไม่มีโพสต์ เริ่มบทสนทนาแรกได้เลย',
              textAlign: TextAlign.center,
              style: AppTypography.base(13, color: AppColors.textSecondary),
            ),
          )
        else
          for (final p in posts) ...[
            _postCard(p),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      mobile: (context) => Scaffold(
        body: SafeArea(bottom: false, child: CenteredContent(child: _feed())),
        bottomNavigationBar: AppBottomNav(
          currentIndex: 3,
          onTap: (i) => NavTargets.onTab(context, i),
        ),
      ),
      desktop: (context) => Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSidebar(
              activeKey: 'community',
              onSelect: (k) => NavTargets.onSidebar(context, k),
            ),
            Expanded(
              child: ColoredBox(
                color: AppColors.background,
                child: CenteredContent(maxWidth: 720, child: _feed()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thread of one post. Pops with the comment count so the feed can update.
class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.postId});

  final int postId;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _input = TextEditingController();
  List<FeedComment>? _items;
  bool _failed = false;
  bool _sending = false;

  CommunityRepository get _repo => AppDependencies.communityRepository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final items = await _repo.comments(widget.postId);
      if (mounted) setState(() => _items = items);
    } on Object catch (e) {
      debugPrint('comments failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final items = await _repo.addComment(widget.postId, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (items == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งความคิดเห็นไม่สำเร็จ')),
      );
      return;
    }
    _input.clear();
    setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final secondary = AppTypography.base(12, color: AppColors.textSecondary);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_items?.length);
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ความคิดเห็น',
              style: AppTypography.base(15, weight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_failed)
              TextButton(onPressed: _load, child: const Text('ลองใหม่'))
            else if (items == null)
              const Center(child: CircularProgressIndicator())
            else if (items.isEmpty)
              Text('ยังไม่มีความคิดเห็น', style: secondary)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${c.author}${c.mine ? ' (คุณ)' : ''}  ',
                                style: AppTypography.base(
                                  12.5,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(
                                text: c.content,
                                style: AppTypography.base(12.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: 'เขียนความคิดเห็น...',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'ส่ง',
                  icon: const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
