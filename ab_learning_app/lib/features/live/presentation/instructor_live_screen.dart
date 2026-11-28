import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/app_dependencies.dart';
import '../data/live_repository.dart';
import 'live_widgets.dart';

/// The instructor's live classes: schedule a new one, open any to start,
/// end or cancel it and answer questions.
class InstructorLiveScreen extends StatefulWidget {
  const InstructorLiveScreen({super.key});

  @override
  State<InstructorLiveScreen> createState() => _InstructorLiveScreenState();
}

class _InstructorLiveScreenState extends State<InstructorLiveScreen> {
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
      final items = await _repo.mine();
      if (mounted) setState(() => _items = items);
    } on Object catch (e) {
      debugPrint('instructor live failed to load: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _open(LiveSession s) async {
    await context.push('/live/${s.id}');
    if (mounted) _load();
  }

  Future<void> _schedule() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _ScheduleDialog(),
    );
    if (created == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Live Sessions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _schedule,
        icon: const Icon(Icons.add),
        label: const Text('ตั้งเวลาไลฟ์'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_failed)
            LiveStateMessage(text: 'โหลดไลฟ์ของคุณไม่สำเร็จ', onRetry: _load)
          else if (items == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items.isEmpty)
            const LiveStateMessage(
              text: 'ยังไม่มีไลฟ์\nกด "ตั้งเวลาไลฟ์" เพื่อนัดผู้เรียน',
            )
          else
            for (final s in items) ...[
              LiveSessionCard(session: s, onTap: () => _open(s)),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog();

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _title = TextEditingController();
  DateTime _at = DateTime.now().add(const Duration(days: 1));
  int _minutes = 60;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (time == null) return;
    setState(() {
      _at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'กรอกชื่อไลฟ์');
      return;
    }
    if (!_at.isAfter(DateTime.now())) {
      setState(() => _error = 'เลือกเวลาในอนาคต');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppDependencies.liveRepository.schedule(
        title: title,
        at: _at,
        minutes: _minutes,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = liveErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = LiveSession(
      id: 0,
      title: '',
      instructor: '',
      scheduledAt: _at,
      durationMinutes: _minutes,
      status: 'upcoming',
    );
    return AlertDialog(
      title: const Text('ตั้งเวลาไลฟ์'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'ชื่อไลฟ์'),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickDate,
            icon: const Icon(Icons.event),
            label: Text(preview.when),
          ),
          const SizedBox(height: 8),
          DropdownButton<int>(
            value: _minutes,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 30, child: Text('30 นาที')),
              DropdownMenuItem(value: 60, child: Text('60 นาที')),
              DropdownMenuItem(value: 90, child: Text('90 นาที')),
              DropdownMenuItem(value: 120, child: Text('120 นาที')),
            ],
            onChanged: _saving ? null : (v) => setState(() => _minutes = v!),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}
