import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/app_dependencies.dart';
import '../../../core/widgets/sub_page_scaffold.dart';
import '../../../data/mock/current_user.dart';
import '../data/live_repository.dart';
import 'live_widgets.dart';

/// Live classes: upcoming / live now, or past ones with their replay.
class LiveListScreen extends StatefulWidget {
  const LiveListScreen({super.key});

  @override
  State<LiveListScreen> createState() => _LiveListScreenState();
}

class _LiveListScreenState extends State<LiveListScreen> {
  bool _past = false;
  List<LiveSession>? _items;
  bool _failed = false;

  LiveRepository get _repo => AppDependencies.liveRepository;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _failed = false;
    });
    try {
      final items = await _repo.sessions(past: _past);
      if (!mounted) return;
      setState(() => _items = items);
    } on Object catch (e) {
      debugPrint('live list failed to load: $e');
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _switch(bool past) {
    if (past == _past) return;
    setState(() => _past = past);
    _load();
  }

  Future<void> _open(LiveSession s) async {
    await context.push('/live/${s.id}');
    if (mounted) _load(); // registration may have changed
  }

  String get _emptyText =>
      _past ? 'ยังไม่มีไลฟ์ย้อนหลัง' : 'ยังไม่มีไลฟ์ที่กำลังจะมาถึง';

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SubPageScaffold(
      title: 'Live',
      fallbackRoute: CurrentUser.homeRouteFor(CurrentUser.role),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('กำลังจะมาถึง')),
            ButtonSegment(value: true, label: Text('ย้อนหลัง')),
          ],
          selected: {_past},
          onSelectionChanged: (v) => _switch(v.first),
        ),
        const SizedBox(height: 12),
        if (_failed)
          LiveStateMessage(text: 'โหลดรายการไลฟ์ไม่สำเร็จ', onRetry: _load)
        else if (items == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          LiveStateMessage(text: _emptyText)
        else
          for (final s in items) ...[
            LiveSessionCard(session: s, onTap: () => _open(s)),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}
