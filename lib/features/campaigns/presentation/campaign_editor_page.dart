import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/core/utils/persian_date.dart';
import 'package:untitled3/features/campaigns/domain/scheduled_campaign.dart';
import 'package:untitled3/features/campaigns/presentation/campaign_contact_picker_page.dart';
import 'package:untitled3/features/campaigns/presentation/persian_date_range_dialog.dart';
import 'package:untitled3/features/contacts/data/contact_storage.dart';
import 'package:untitled3/features/contacts/domain/contact.dart';
import 'package:untitled3/features/contacts/domain/sms_campaign.dart';

enum _IntervalUnit { seconds, minutes }

class CampaignEditorPage extends StatefulWidget {
  const CampaignEditorPage({
    super.key,
    required this.campaigns,
    this.initialCampaign,
    this.activeRuntime,
  });

  final List<ScheduledCampaign> campaigns;
  final ScheduledCampaign? initialCampaign;
  final SmsCampaign? activeRuntime;

  @override
  State<CampaignEditorPage> createState() => _CampaignEditorPageState();
}

class _CampaignEditorPageState extends State<CampaignEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _intervalController = TextEditingController(text: '30');

  late DateTime _startDate;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late CampaignAudience _audience;
  late List<CampaignRecipient> _selectedRecipients;
  _IntervalUnit _intervalUnit = _IntervalUnit.seconds;
  bool _loadingContacts = false;

  bool get _editing => widget.initialCampaign != null;

  int get _intervalSeconds {
    final normalized = normalizePhoneNumber(_intervalController.text);
    final value = int.tryParse(normalized) ?? 0;
    return _intervalUnit == _IntervalUnit.minutes ? value * 60 : value;
  }

  int get _dailyStartMinute => _startTime.hour * 60 + _startTime.minute;
  int get _dailyEndMinute => _endTime.hour * 60 + _endTime.minute;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCampaign;
    if (initial == null) {
      final tomorrow = dateOnly(DateTime.now()).add(const Duration(days: 1));
      _startDate = tomorrow;
      _endDate = tomorrow;
      _startTime = const TimeOfDay(hour: 8, minute: 0);
      _endTime = const TimeOfDay(hour: 20, minute: 0);
      _audience = CampaignAudience.allAtStart;
      _selectedRecipients = <CampaignRecipient>[];
      return;
    }

    _titleController.text = initial.title;
    _messageController.text = initial.message;
    _startDate = initial.startDate;
    _endDate = initial.endDate;
    _startTime = _timeFromMinute(initial.dailyStartMinute);
    _endTime = _timeFromMinute(initial.dailyEndMinute);
    _audience = initial.audience;
    _selectedRecipients = List<CampaignRecipient>.from(
      initial.selectedRecipients,
    );
    if (initial.intervalSeconds >= 60 && initial.intervalSeconds % 60 == 0) {
      _intervalUnit = _IntervalUnit.minutes;
      _intervalController.text = '${initial.intervalSeconds ~/ 60}';
    } else {
      _intervalController.text = '${initial.intervalSeconds}';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final result = await showPersianDateRangeDialog(
      context: context,
      initialStart: _startDate,
      initialEnd: _endDate,
    );
    if (result == null || !mounted) return;
    setState(() {
      _startDate = dateOnly(result.start);
      _endDate = dateOnly(result.end);
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final result = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
      helpText: start ? 'شروع ارسال روزانه' : 'پایان ارسال روزانه',
      cancelText: 'انصراف',
      confirmText: 'تأیید',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (start) {
        _startTime = result;
      } else {
        _endTime = result;
      }
    });
  }

  Future<void> _pickContacts() async {
    if (_loadingContacts) return;
    setState(() => _loadingContacts = true);
    final contacts = await ContactStorage.load();
    if (!mounted) return;
    setState(() => _loadingContacts = false);
    if (contacts.isEmpty) {
      _snack('ابتدا از صفحه مخاطب‌ها حداقل یک مخاطب اضافه کنید.');
      return;
    }
    contacts.sort((first, second) {
      return normalizeContactSearch(
        first.name,
      ).compareTo(normalizeContactSearch(second.name));
    });
    final selected = await Navigator.of(context).push<List<Contact>>(
      MaterialPageRoute<List<Contact>>(
        builder: (_) => CampaignContactPickerPage(
          contacts: contacts,
          selectedIds: _selectedRecipients
              .map((recipient) => recipient.contactId)
              .toSet(),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedRecipients = selected
          .map(CampaignRecipient.fromContact)
          .toList(growable: false);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_dailyEndMinute <= _dailyStartMinute) {
      _snack('ساعت پایان باید بعد از ساعت شروع روزانه باشد.');
      return;
    }
    if (_audience == CampaignAudience.selected && _selectedRecipients.isEmpty) {
      _snack('حداقل یک مخاطب را انتخاب کنید.');
      return;
    }

    final now = DateTime.now();
    final initial = widget.initialCampaign;
    final candidate = ScheduledCampaign(
      id: initial?.id ?? now.microsecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      message: _messageController.text.trim(),
      audience: _audience,
      selectedRecipients: _audience == CampaignAudience.selected
          ? List<CampaignRecipient>.unmodifiable(_selectedRecipients)
          : const [],
      startDate: dateOnly(_startDate),
      endDate: dateOnly(_endDate),
      dailyStartMinute: _dailyStartMinute,
      dailyEndMinute: _dailyEndMinute,
      intervalSeconds: _intervalSeconds,
      createdAt: initial?.createdAt ?? now,
      updatedAt: now,
    );

    if (!candidate.endsAt.isAfter(now)) {
      _snack('پایان کمپین باید در آینده باشد.');
      return;
    }
    ScheduledCampaign? conflict;
    for (final campaign in widget.campaigns) {
      if (campaign.id != candidate.id &&
          scheduledCampaignsOverlap(candidate, campaign)) {
        conflict = campaign;
        break;
      }
    }
    if (conflict != null) {
      _snack('زمان انتخاب‌شده با کمپین «${conflict.title}» تداخل دارد.');
      return;
    }
    final active = widget.activeRuntime;
    if (active != null &&
        active.scheduledCampaignId != candidate.id &&
        scheduledCampaignOverlapsRange(
          candidate,
          active.startsAt,
          active.endsAt,
        )) {
      _snack('این زمان با ارسال در حال اجرا تداخل دارد.');
      return;
    }
    Navigator.of(context).pop(candidate);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capacity = _capacity;
    final selectedCount = _selectedRecipients.length;
    final insufficient =
        _audience == CampaignAudience.selected &&
        selectedCount > 0 &&
        capacity < selectedCount;

    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'ویرایش کمپین' : 'کمپین جدید')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _IntroBanner(editing: _editing),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'پیام کمپین',
              subtitle: 'یک عنوان کوتاه و متن واضح بنویسید.',
              icon: Icons.campaign_rounded,
              color: AppColors.secondary,
              child: Column(
                children: [
                  TextFormField(
                    controller: _titleController,
                    maxLength: 60,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'عنوان کمپین',
                      hintText: 'مثلاً تبریک روز مربی',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'عنوان کمپین را وارد کنید'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _messageController,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'متن پیامک',
                      hintText: 'متنی که برای مخاطبان ارسال می‌شود',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.sms_outlined),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'متن پیام را وارد کنید'
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'زمان‌بندی شمسی',
              subtitle: 'در هر روز فقط داخل ساعت تعیین‌شده ارسال می‌شود.',
              icon: Icons.event_available_rounded,
              color: AppColors.accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ValueButton(
                    icon: Icons.date_range_rounded,
                    label: 'بازه تاریخ',
                    value: formatPersianDateRange(_startDate, _endDate),
                    onTap: _pickDateRange,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _ValueButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'شروع روزانه',
                          value: _formatTime(_startTime),
                          onTap: () => _pickTime(start: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ValueButton(
                          icon: Icons.stop_rounded,
                          label: 'پایان روزانه',
                          value: _formatTime(_endTime),
                          onTap: () => _pickTime(start: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'فاصله بین هر دو پیامک',
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
                            labelText: 'فاصله',
                            prefixIcon: Icon(Icons.timer_outlined),
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (_) =>
                              _intervalSeconds <= 0 ? 'بزرگ‌تر از صفر' : null,
                        ),
                      ),
                      const SizedBox(width: 9),
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
                        showSelectedIcon: false,
                        onSelectionChanged: (value) {
                          setState(() => _intervalUnit = value.first);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'گیرندگان',
              subtitle: 'فهرست همه در لحظه شروع یا افراد مشخص.',
              icon: Icons.groups_rounded,
              color: AppColors.primary,
              child: Column(
                children: [
                  _AudienceChoice(
                    selected: _audience == CampaignAudience.allAtStart,
                    icon: Icons.all_inclusive_rounded,
                    title: 'ارسال به همه',
                    subtitle:
                        'همه مخاطبان موجود دقیقاً هنگام اولین ارسال انتخاب می‌شوند.',
                    onTap: () =>
                        setState(() => _audience = CampaignAudience.allAtStart),
                  ),
                  const SizedBox(height: 8),
                  _AudienceChoice(
                    selected: _audience == CampaignAudience.selected,
                    icon: Icons.rule_rounded,
                    title: 'مخاطبان انتخابی',
                    subtitle: selectedCount == 0
                        ? 'افراد موردنظر را با جست‌وجو انتخاب کنید.'
                        : '$selectedCount مخاطب برای این کمپین انتخاب شده‌اند.',
                    onTap: () =>
                        setState(() => _audience = CampaignAudience.selected),
                  ),
                  if (_audience == CampaignAudience.selected) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loadingContacts ? null : _pickContacts,
                      icon: _loadingContacts
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_search_rounded),
                      label: Text(
                        selectedCount == 0
                            ? 'انتخاب مخاطبان'
                            : 'تغییر $selectedCount مخاطب',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _CampaignSummary(
              dateRange: formatPersianDateRange(_startDate, _endDate),
              timeRange:
                  '${_formatTime(_startTime)} تا ${_formatTime(_endTime)}',
              interval: _intervalLabel,
              audience: _audience == CampaignAudience.allAtStart
                  ? 'همه مخاطبان در لحظه شروع'
                  : '$selectedCount مخاطب انتخابی',
              capacity: capacity,
              insufficient: insufficient,
              missingCount: insufficient ? selectedCount - capacity : 0,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: FilledButton.icon(
          onPressed: _submit,
          icon: Icon(_editing ? Icons.save_rounded : Icons.add_task_rounded),
          label: Text(_editing ? 'ذخیره تغییرات' : 'ذخیره و فعال‌سازی کمپین'),
        ),
      ),
    );
  }

  int get _capacity {
    if (_intervalSeconds <= 0 || _dailyEndMinute <= _dailyStartMinute) return 0;
    final days = dateOnly(_endDate).difference(dateOnly(_startDate)).inDays + 1;
    final secondsPerDay = (_dailyEndMinute - _dailyStartMinute) * 60;
    final perDay = ((secondsPerDay - 1) ~/ _intervalSeconds) + 1;
    return days * perDay;
  }

  String get _intervalLabel {
    final value = normalizePhoneNumber(_intervalController.text);
    return '$value ${_intervalUnit == _IntervalUnit.minutes ? 'دقیقه' : 'ثانیه'}';
  }

  String _formatTime(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}

class _IntroBanner extends StatelessWidget {
  const _IntroBanner({required this.editing});

  final bool editing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.secondary.withValues(alpha: 0.15),
            AppColors.accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              editing
                  ? 'تا قبل از رسیدن روز شروع، همه جزئیات قابل ویرایش است.'
                  : 'کمپین ذخیره می‌شود و سرویس در روزها و ساعت‌های تعیین‌شده آن را اجرا می‌کند.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.55,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          child,
        ],
      ),
    );
  }
}

class _ValueButton extends StatelessWidget {
  const _ValueButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 21),
              const SizedBox(width: 9),
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
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more_rounded, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudienceChoice extends StatelessWidget {
  const _AudienceChoice({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.08)
          : AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Color(0xFF00382E),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampaignSummary extends StatelessWidget {
  const _CampaignSummary({
    required this.dateRange,
    required this.timeRange,
    required this.interval,
    required this.audience,
    required this.capacity,
    required this.insufficient,
    required this.missingCount,
  });

  final String dateRange;
  final String timeRange;
  final String interval;
  final String audience;
  final int capacity;
  final bool insufficient;
  final int missingCount;

  @override
  Widget build(BuildContext context) {
    final color = insufficient ? AppColors.warning : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                insufficient
                    ? Icons.warning_amber_rounded
                    : Icons.fact_check_outlined,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                insufficient ? 'زمان برای همه کافی نیست' : 'خلاصه اجرای کمپین',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SummaryLine(icon: Icons.date_range_rounded, text: dateRange),
          _SummaryLine(icon: Icons.schedule_rounded, text: timeRange),
          _SummaryLine(icon: Icons.timer_outlined, text: 'هر $interval'),
          _SummaryLine(icon: Icons.groups_2_outlined, text: audience),
          const SizedBox(height: 5),
          Text(
            insufficient
                ? 'با این فاصله حداکثر $capacity پیام جا می‌شود و $missingCount مخاطب بدون ارسال می‌ماند.'
                : 'ظرفیت زمانی این بازه حداکثر $capacity پیامک است.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: insufficient
                  ? AppColors.warning
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

TimeOfDay _timeFromMinute(int minute) {
  return TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
}
