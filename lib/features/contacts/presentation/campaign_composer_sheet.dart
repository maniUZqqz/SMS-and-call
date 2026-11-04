import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/contacts/domain/contact.dart';
import 'package:untitled3/features/contacts/domain/sms_campaign.dart';

enum _IntervalUnit { seconds, minutes }

class CampaignComposerSheet extends StatefulWidget {
  const CampaignComposerSheet({super.key, required this.contacts});

  final List<Contact> contacts;

  @override
  State<CampaignComposerSheet> createState() => _CampaignComposerSheetState();
}

class _CampaignComposerSheetState extends State<CampaignComposerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _intervalController = TextEditingController(text: '30');
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  _IntervalUnit _intervalUnit = _IntervalUnit.seconds;

  bool get _isGroup => widget.contacts.length > 1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startTime = TimeOfDay.fromDateTime(now);
    _endTime = TimeOfDay.fromDateTime(now.add(const Duration(hours: 1)));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  int get _intervalSeconds {
    final normalized = normalizePhoneNumber(_intervalController.text);
    final value = int.tryParse(normalized) ?? 0;
    return _intervalUnit == _IntervalUnit.minutes ? value * 60 : value;
  }

  ({DateTime start, DateTime end}) _resolveWindow() {
    final now = DateTime.now();
    var start = DateTime(
      now.year,
      now.month,
      now.day,
      _startTime.hour,
      _startTime.minute,
    );

    if (start.isBefore(now)) {
      final elapsed = now.difference(start);
      if (elapsed <= const Duration(minutes: 2)) {
        start = now;
      } else {
        start = start.add(const Duration(days: 1));
      }
    }

    var end = DateTime(
      start.year,
      start.month,
      start.day,
      _endTime.hour,
      _endTime.minute,
    );
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return (start: start, end: end);
  }

  Future<void> _pickTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
      helpText: start ? 'ساعت شروع ارسال' : 'ساعت پایان ارسال',
      cancelText: 'انصراف',
      confirmText: 'تأیید',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _startTime = selected;
      } else {
        _endTime = selected;
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final window = _isGroup
        ? _resolveWindow()
        : (start: now, end: now.add(const Duration(minutes: 5)));
    final campaign = SmsCampaign.create(
      message: _messageController.text,
      contacts: widget.contacts,
      intervalSeconds: _isGroup ? _intervalSeconds : 0,
      startsAt: window.start,
      endsAt: window.end,
    );
    Navigator.of(context).pop(campaign);
  }

  String _timeLabel(BuildContext context, TimeOfDay value) {
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(value, alwaysUse24HourFormat: true);
  }

  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final days = target.difference(today).inDays;
    if (days == 0) return 'امروز';
    if (days == 1) return 'فردا';
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final window = _resolveWindow();
    final capacity = campaignWindowCapacity(
      startsAt: window.start,
      endsAt: window.end,
      intervalSeconds: _intervalSeconds,
    );
    final limited = _isGroup && capacity < widget.contacts.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isGroup ? 'ارسال گروهی' : 'ارسال پیامک',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _isGroup
                              ? '${widget.contacts.length} مخاطب انتخاب شده‌اند'
                              : 'به ${widget.contacts.first.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _messageController,
                autofocus: true,
                minLines: 3,
                maxLines: 7,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'متن پیام',
                  hintText: 'پیامی که باید ارسال شود را بنویسید',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.sms_outlined),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'متن پیام را وارد کنید'
                    : null,
              ),
              if (_isGroup) ...[
                const SizedBox(height: 18),
                Text(
                  'فاصله بین پیام‌ها',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _intervalController,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9۰-۹٠-٩]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'مقدار فاصله',
                          prefixIcon: Icon(Icons.timer_outlined),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (_) => _intervalSeconds <= 0
                            ? 'عدد بزرگ‌تر از صفر وارد کنید'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SegmentedButton<_IntervalUnit>(
                      segments: const [
                        ButtonSegment(
                          value: _IntervalUnit.seconds,
                          label: Text('ثانیه'),
                        ),
                        ButtonSegment(
                          value: _IntervalUnit.minutes,
                          label: Text('دقیقه'),
                        ),
                      ],
                      selected: {_intervalUnit},
                      onSelectionChanged: (selection) {
                        setState(() => _intervalUnit = selection.first);
                      },
                      showSelectedIcon: false,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'بازه مجاز ارسال',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'اگر زمان تمام شود، مخاطبان باقی‌مانده پیام دریافت نمی‌کنند.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _TimeButton(
                        label: 'شروع',
                        value: _timeLabel(context, _startTime),
                        icon: Icons.play_arrow_rounded,
                        onTap: () => _pickTime(start: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TimeButton(
                        label: 'پایان',
                        value: _timeLabel(context, _endTime),
                        icon: Icons.stop_rounded,
                        onTap: () => _pickTime(start: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (limited ? AppColors.warning : AppColors.primary)
                        .withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: (limited ? AppColors.warning : AppColors.primary)
                          .withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        limited
                            ? Icons.warning_amber_rounded
                            : Icons.schedule_send_rounded,
                        color: limited ? AppColors.warning : AppColors.primary,
                        size: 21,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          limited
                              ? 'در این بازه حداکثر $capacity پیام ارسال می‌شود؛ ${widget.contacts.length - capacity} مخاطب باقی‌مانده ارسال نخواهد شد.'
                              : 'ارسال از ${_dayLabel(window.start)} ساعت ${_timeLabel(context, TimeOfDay.fromDateTime(window.start))} تا ${_dayLabel(window.end)} ساعت ${_timeLabel(context, TimeOfDay.fromDateTime(window.end))} انجام می‌شود.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: limited
                                ? AppColors.warning
                                : theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('انصراف'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.send_rounded),
                      label: Text(
                        _isGroup
                            ? 'شروع ارسال به ${widget.contacts.length} نفر'
                            : 'ارسال پیامک',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const Icon(Icons.expand_more_rounded, size: 18),
        ],
      ),
    );
  }
}
