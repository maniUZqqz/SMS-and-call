import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/core/storage/app_storage.dart';
import 'package:sms_and_call/core/theme/app_theme.dart';
import 'package:sms_and_call/features/calls/data/recording_repository.dart';
import 'package:sms_and_call/features/calls/domain/call_models.dart';
import 'package:sms_and_call/features/calls/presentation/call_format.dart';
import 'package:sms_and_call/features/calls/services/call_cycle.dart';
import 'package:sms_and_call/features/calls/services/recording_pipeline.dart';

/// جزئیات یک ضبط: پخش صدا، متن، اشتراک‌گذاری و حذف.
class RecordingDetailPage extends StatefulWidget {
  const RecordingDetailPage({super.key, required this.recordingId, required this.repository});

  final String recordingId;
  final RecordingRepository repository;

  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  CallRecording? _recording;
  String _transcript = '';
  PlayerState _player = PlayerState.idle;
  Timer? _ticker;
  bool _working = false;
  bool _dragging = false;
  double _dragValue = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _ticker = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      final recording = _recording;
      if (recording == null || !recording.hasAudio) return;
      final state = await SmsBridge.playerState();
      if (!mounted || _dragging) return;
      setState(() => _player = state.path == recording.audioPath ? state : PlayerState.idle);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(SmsBridge.playerStop());
    super.dispose();
  }

  Future<void> _load() async {
    final recording = await widget.repository.get(widget.recordingId);
    final text = recording == null ? '' : await widget.repository.readTranscript(recording.id);
    if (!mounted) return;
    setState(() {
      _recording = recording;
      _transcript = text;
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _togglePlay() async {
    final recording = _recording;
    if (recording == null || !recording.hasAudio) return;
    if (_player.path == recording.audioPath && _player.positionMs < _player.durationMs) {
      if (_player.playing) {
        await SmsBridge.playerPause();
      } else {
        await SmsBridge.playerResume();
      }
    } else {
      final ok = await SmsBridge.playerPlay(recording.audioPath);
      if (!ok) _snack('پخش این فایل ممکن نشد.');
    }
  }

  Future<void> _transcribeNow() async {
    final recording = _recording;
    if (recording == null || _working) return;
    setState(() => _working = true);
    try {
      final cycle = CallCycle();
      await cycle.refreshSettings();
      final RecordingPipeline pipeline = cycle.buildPipeline();
      await pipeline.requeue(recording.id, retranscribe: true);
      final fresh = await widget.repository.get(recording.id);
      if (fresh != null) await pipeline.processOne(fresh);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    await _load();
    final result = _recording;
    if (result != null && result.transcriptStatus == TranscriptStatus.failed) {
      _snack(result.transcriptError.isEmpty ? 'تبدیل به متن ناموفق بود.' : result.transcriptError);
    }
  }

  String _textForExport(CallRecording r) {
    final b = StringBuffer()
      ..writeln('ضبط تماس — ${r.title}')
      ..writeln('شماره: ${r.number.isEmpty ? 'نامشخص' : r.number}')
      ..writeln('زمان: ${formatCallWhen(r.when)}')
      ..writeln('نوع: ${callDirectionLabel(r.direction)}');
    final d = r.callDuration;
    if (d != null) b.writeln('مدت تماس: ${formatCallDuration(d)}');
    b
      ..writeln('────────────')
      ..writeln(_transcript);
    return b.toString();
  }

  Future<void> _shareText(CallRecording r) async {
    final ok = await SmsBridge.shareText(_textForExport(r), subject: 'متن تماس ${r.title}');
    if (!ok) _snack('منوی اشتراک‌گذاری باز نشد.');
  }

  Future<void> _exportFile(CallRecording r) async {
    final dir = Directory('${await AppDir.path()}/exports');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = r.title.replaceAll(RegExp(r'[^\w؀-ۿ]+'), '_');
    final file = File('${dir.path}/call_${safe}_${r.when.millisecondsSinceEpoch}.txt');
    await file.writeAsString(_textForExport(r));
    final ok = await SmsBridge.shareFile(file.path, mime: 'text/plain', subject: 'متن تماس ${r.title}');
    if (!ok) _snack('فایل ساخته شد ولی منوی اشتراک‌گذاری باز نشد: ${file.path}');
  }

  Future<void> _shareAudio(CallRecording r) async {
    final ok = await SmsBridge.shareFile(r.audioPath, mime: r.mime.isEmpty ? 'audio/*' : r.mime);
    if (!ok) _snack('اشتراک‌گذاری فایل صوتی ممکن نشد.');
  }

  Future<void> _delete(CallRecording r) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('حذف'),
        children: [
          if (r.hasAudio)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('audio'),
              child: const Text('فقط فایل صوتی (متن و اطلاعات تماس بماند)'),
            ),
          if (_transcript.isNotEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('text'),
              child: const Text('فقط متن (فایل صوتی بماند)'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('all'),
            child: const Text('همه‌چیز (صدا، متن و ردیف)', style: TextStyle(color: AppColors.error)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await SmsBridge.playerStop();
    switch (choice) {
      case 'audio':
        await widget.repository.delete(r.id, deleteTranscript: false);
      case 'text':
        await widget.repository.delete(r.id, deleteAudio: false);
      default:
        await widget.repository.delete(r.id);
    }
    if (choice == 'all') {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    await _load();
    _snack('حذف شد. نسخه‌ی اصلیِ ضبط‌کننده‌ی گوشی (در پوشه‌ی خودش) دست‌نخورده می‌ماند.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _recording;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ضبط تماس')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final color = transcriptStatusColor(r.transcriptStatus);
    final duration = _player.durationMs > 0 ? _player.durationMs : r.durationMs;
    final position = _dragging ? _dragValue : _player.positionMs.toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: () => _delete(r),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _card(
            theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(callDirectionIcon(r.direction), color: AppColors.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.number.isEmpty ? 'شماره‌ی نامشخص' : r.number,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusPill(label: formatCallWhen(r.when), color: AppColors.secondary, icon: Icons.schedule_rounded),
                    StatusPill(label: callDirectionLabel(r.direction), color: AppColors.accent),
                    if (r.callDuration != null)
                      StatusPill(label: 'مدت ${formatCallDuration(r.callDuration!)}', color: AppColors.primary),
                    StatusPill(
                      label: r.linked ? 'به تاریخچه‌ی تماس وصل است' : 'به تماسی در تاریخچه وصل نشده',
                      color: r.linked ? AppColors.success : AppColors.warning,
                      icon: r.linked ? Icons.link_rounded : Icons.link_off_rounded,
                    ),
                    StatusPill(
                      label: switch (r.source) {
                        RecordingSource.phoneRecorder => 'ضبط‌کننده‌ی گوشی',
                        RecordingSource.inApp => 'ضبط داخلی (آزمایشی)',
                        RecordingSource.manual => 'ضبط دستی',
                      },
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            theme,
            child: r.hasAudio
                ? Column(
                    children: [
                      Row(
                        children: [
                          IconButton.filled(
                            iconSize: 30,
                            onPressed: _togglePlay,
                            icon: Icon(_player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          ),
                          Expanded(
                            child: Slider(
                              value: duration <= 0 ? 0 : position.clamp(0, duration.toDouble()),
                              max: duration <= 0 ? 1 : duration.toDouble(),
                              onChangeStart: (_) => _dragging = true,
                              onChanged: (v) => setState(() => _dragValue = v),
                              onChangeEnd: (v) async {
                                _dragging = false;
                                await SmsBridge.playerSeek(v.round());
                              },
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(formatCallDuration(Duration(milliseconds: position.round())), style: theme.textTheme.bodySmall),
                            Text(formatCallDuration(Duration(milliseconds: duration)), style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => _shareAudio(r),
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: const Text('ارسال فایل صوتی'),
                        ),
                      ),
                    ],
                  )
                : Text(
                    'فایل صوتی حذف شده است؛ فقط متن و اطلاعات تماس مانده.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
          ),
          const SizedBox(height: 12),
          _card(
            theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('متن مکالمه', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    StatusPill(label: transcriptStatusLabel(r.transcriptStatus), color: color),
                  ],
                ),
                const SizedBox(height: 10),
                if (_transcript.isNotEmpty)
                  SelectableText(
                    _transcript,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.9),
                  )
                else if (r.transcriptStatus == TranscriptStatus.failed && r.transcriptError.isNotEmpty)
                  Text(
                    r.transcriptError,
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error, height: 1.7),
                  )
                else
                  Text(
                    r.transcriptStatus == TranscriptStatus.queued || r.transcriptStatus == TranscriptStatus.running
                        ? 'در صف تبدیل به متن است…'
                        : 'هنوز متنی ساخته نشده. سرویس تبدیل به متن را در «تنظیمات ضبط تماس» وارد کنید.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (r.hasAudio && r.transcriptStatus != TranscriptStatus.running)
                      FilledButton.icon(
                        onPressed: _working ? null : _transcribeNow,
                        icon: _working
                            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.record_voice_over_rounded, size: 18),
                        label: Text(_transcript.isEmpty ? 'تبدیل به متن' : 'تبدیل دوباره'),
                      ),
                    if (_transcript.isNotEmpty) ...[
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _transcript));
                          _snack('متن کپی شد.');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('کپی'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _shareText(r),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('اشتراک متن'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportFile(r),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text('فایل متنی'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(ThemeData theme, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}
