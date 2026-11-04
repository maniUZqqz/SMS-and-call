import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/contacts/data/campaign_storage.dart';
import 'package:untitled3/features/contacts/data/contact_importer.dart';
import 'package:untitled3/features/contacts/data/contact_storage.dart';
import 'package:untitled3/features/contacts/domain/contact.dart';
import 'package:untitled3/features/contacts/domain/sms_campaign.dart';
import 'package:untitled3/features/contacts/presentation/campaign_composer_sheet.dart';
import 'package:untitled3/features/contacts/presentation/contact_editor_sheet.dart';

enum _ContactAction { edit, delete }

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key, required this.onEnsureReady});

  final Future<bool> Function() onEnsureReady;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};

  StreamSubscription<Map<String, dynamic>?>? _statusSubscription;
  StreamSubscription<Map<String, dynamic>?>? _rejectedSubscription;

  List<Contact> _contacts = const [];
  SmsCampaign? _activeCampaign;
  CampaignState? _campaignState;
  String? _currentContact;
  String _query = '';
  bool _loading = true;
  bool _importing = false;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final service = FlutterBackgroundService();
    _statusSubscription = service
        .on('campaignStatus')
        .listen(_onCampaignStatus);
    _rejectedSubscription = service
        .on('campaignRejected')
        .listen(_onCampaignRejected);
    unawaited(_loadData());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      service.invoke('requestCampaignStatus');
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _rejectedSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final contacts = await ContactStorage.load();
    final active = await CampaignStorage.loadActive();
    _sortContacts(contacts);
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _activeCampaign = active;
      if (active != null && _campaignState == null) {
        _campaignState = DateTime.now().isBefore(active.startsAt)
            ? CampaignState.waiting
            : CampaignState.queued;
      }
      _selectedIds.removeWhere(
        (id) => !contacts.any((contact) => contact.id == id),
      );
      _loading = false;
    });
    FlutterBackgroundService().invoke('requestCampaignStatus');
  }

  void _sortContacts(List<Contact> contacts) {
    contacts.sort((first, second) {
      final byDate = second.effectiveAddedAt.compareTo(first.effectiveAddedAt);
      if (byDate != 0) return byDate;
      return normalizeContactSearch(
        first.name,
      ).compareTo(normalizeContactSearch(second.name));
    });
  }

  void _onCampaignStatus(Map<String, dynamic>? event) {
    if (!mounted || event == null) return;
    final stateName = (event['state'] ?? '').toString();
    if (stateName == 'idle') {
      setState(() {
        _activeCampaign = null;
        _campaignState = null;
        _currentContact = null;
      });
      return;
    }

    final rawCampaign = event['campaign'];
    if (rawCampaign is! Map) return;

    final state = CampaignState.values.firstWhere(
      (value) => value.name == stateName,
      orElse: () => CampaignState.failed,
    );
    final campaign = SmsCampaign.fromJson(
      Map<String, dynamic>.from(rawCampaign),
    );
    final terminal = {
      CampaignState.completed,
      CampaignState.cancelled,
      CampaignState.windowEnded,
      CampaignState.failed,
    }.contains(state);

    setState(() {
      _activeCampaign = terminal ? null : campaign;
      _campaignState = terminal ? null : state;
      _currentContact = terminal
          ? null
          : (event['currentContact']?.toString() ?? _currentContact);
    });

    if (terminal) unawaited(_finishCampaignUi(state));
  }

  Future<void> _finishCampaignUi(CampaignState state) async {
    if (!mounted) return;
    final message = switch (state) {
      CampaignState.completed => 'ارسال کمپین با موفقیت تمام شد.',
      CampaignState.cancelled => 'ارسال کمپین متوقف شد.',
      CampaignState.windowEnded =>
        'بازه زمانی تمام شد؛ پیام دیگری ارسال نمی‌شود.',
      _ => 'کمپین به‌دلیل خطا متوقف شد.',
    };
    _snack(message);
  }

  void _onCampaignRejected(Map<String, dynamic>? event) {
    if (!mounted) return;
    _snack(event?['message']?.toString() ?? 'شروع کمپین امکان‌پذیر نیست.');
    unawaited(_reloadActiveCampaign());
  }

  Future<void> _reloadActiveCampaign() async {
    final active = await CampaignStorage.loadActive();
    if (!mounted) return;
    setState(() => _activeCampaign = active);
  }

  Future<Contact?> _openContactEditor([Contact? contact]) {
    return showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ContactEditorSheet(contact: contact),
    );
  }

  Future<void> _addContact() async {
    final contact = await _openContactEditor();
    if (contact == null || !mounted) return;

    final updated = [..._contacts, contact];
    _sortContacts(updated);
    await _saveContacts(updated, successMessage: 'مخاطب اضافه شد.');
  }

  Future<void> _editContact(Contact original) async {
    final edited = await _openContactEditor(original);
    if (edited == null || !mounted) return;

    final updated = _contacts
        .map((contact) => contact.id == original.id ? edited : contact)
        .toList();
    _sortContacts(updated);
    await _saveContacts(updated, successMessage: 'تغییرات ذخیره شد.');
  }

  Future<void> _deleteContact(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
        title: const Text('حذف مخاطب'),
        content: Text('«${contact.name}» از فهرست مخاطبان حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final updated = _contacts.where((item) => item.id != contact.id).toList();
    _selectedIds.remove(contact.id);
    await _saveContacts(updated, successMessage: 'مخاطب حذف شد.');
  }

  Future<bool> _saveContacts(
    List<Contact> contacts, {
    String? successMessage,
  }) async {
    try {
      await ContactStorage.save(contacts);
      if (!mounted) return false;
      setState(() => _contacts = contacts);
      if (successMessage != null) _snack(successMessage);
      return true;
    } catch (_) {
      if (mounted) _snack('ذخیره مخاطبان انجام نشد. دوباره تلاش کنید.');
      return false;
    }
  }

  Future<void> _importContacts() async {
    if (_importing) return;
    PickedContactFile? picked;
    List<Contact>? importedContacts;
    ContactImportResult? importResult;
    try {
      picked = await SmsBridge.pickContactFile();
      if (picked == null || !mounted) return;
      setState(() => _importing = true);

      importResult = await ContactImporter.parse(
        path: picked.path,
        fileName: picked.name,
      );
      final batchTime = DateTime.now();
      importedContacts = List<Contact>.generate(importResult.contacts.length, (
        index,
      ) {
        final item = importResult!.contacts[index];
        final addedAt = batchTime.add(
          Duration(microseconds: importResult.contacts.length - index),
        );
        return Contact(
          id: '${batchTime.microsecondsSinceEpoch}-$index',
          name: item.name,
          phone: item.phone,
          note: item.note,
          addedAt: addedAt,
        );
      }, growable: false);
      final updated = [..._contacts, ...importedContacts];
      _sortContacts(updated);
      final saved = await _saveContacts(updated);
      if (!saved || !mounted) {
        importedContacts = null;
        return;
      }

      _searchController.clear();
      setState(() {
        _query = '';
        _selectedIds
          ..clear()
          ..addAll(importedContacts!.map((contact) => contact.id));
      });
      final skipped = importResult.skippedRows > 0
          ? ' · ${importResult.skippedRows} ردیف ناقص رد شد'
          : '';
      _snack('${importedContacts.length} مخاطب اضافه و انتخاب شد$skipped.');
    } on FormatException catch (error) {
      if (mounted) _snack(error.message);
      importedContacts = null;
    } catch (error) {
      if (mounted) _snack('واردکردن فایل انجام نشد: $error');
      importedContacts = null;
    } finally {
      if (picked != null) {
        try {
          await File(picked.path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _importing = false);
    }

    if (importedContacts != null && importedContacts.isNotEmpty && mounted) {
      await _composeFor(importedContacts);
    }
  }

  void _toggleSelection(Contact contact) {
    setState(() {
      if (!_selectedIds.add(contact.id)) {
        _selectedIds.remove(contact.id);
      }
    });
  }

  void _selectAllVisible(List<Contact> visibleContacts) {
    setState(() {
      final allSelected = visibleContacts.every(
        (contact) => _selectedIds.contains(contact.id),
      );
      if (allSelected) {
        _selectedIds.removeAll(visibleContacts.map((contact) => contact.id));
      } else {
        _selectedIds.addAll(visibleContacts.map((contact) => contact.id));
      }
    });
  }

  List<Contact> _contactsOnDay(DateTime day) {
    return _contacts
        .where((contact) => _sameDay(contact.effectiveAddedAt, day))
        .toList(growable: false);
  }

  void _toggleDaySelection(DateTime day) {
    final contacts = _contactsOnDay(day);
    setState(() {
      final allSelected = contacts.every(
        (contact) => _selectedIds.contains(contact.id),
      );
      if (allSelected) {
        _selectedIds.removeAll(contacts.map((contact) => contact.id));
      } else {
        _selectedIds.addAll(contacts.map((contact) => contact.id));
      }
    });
  }

  List<_ContactGroup> _groupContacts(List<Contact> contacts) {
    final grouped = <DateTime, List<Contact>>{};
    for (final contact in contacts) {
      final value = contact.effectiveAddedAt;
      final day = DateTime(value.year, value.month, value.day);
      grouped.putIfAbsent(day, () => <Contact>[]).add(contact);
    }
    return grouped.entries
        .map((entry) => _ContactGroup(day: entry.key, contacts: entry.value))
        .toList(growable: false);
  }

  Future<void> _composeFor(List<Contact> contacts) async {
    if (contacts.isEmpty) return;
    if (_activeCampaign != null) {
      _snack(
        _activeCampaign!.scheduledCampaignId == null
            ? 'ابتدا ارسال در حال اجرا را تمام یا متوقف کنید.'
            : 'یک کمپین زمان‌بندی‌شده در حال اجراست؛ کمی بعد دوباره تلاش کنید.',
      );
      return;
    }

    final campaign = await showModalBottomSheet<SmsCampaign>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => CampaignComposerSheet(contacts: contacts),
    );
    if (campaign == null || !mounted) return;

    final ready = await widget.onEnsureReady();
    if (!mounted) return;
    if (!ready) {
      _snack('برای ارسال پیامک، مجوز ارسال و سرویس برنامه باید فعال باشد.');
      return;
    }

    setState(() {
      _activeCampaign = campaign;
      _campaignState = CampaignState.queued;
      _currentContact = null;
      _selectedIds.clear();
    });
    FlutterBackgroundService().invoke('startCampaign', campaign.toJson());
    _snack(
      campaign.startsAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))
          ? 'کمپین برای زمان انتخاب‌شده در صف قرار گرفت.'
          : 'ارسال پیامک شروع شد.',
    );
  }

  void _cancelCampaign() {
    FlutterBackgroundService().invoke('cancelCampaign');
    _snack('درخواست توقف ارسال ثبت شد.');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final visibleContacts = _contacts
        .where((contact) => contactMatchesSearch(contact, _query))
        .toList(growable: false);
    final groups = _groupContacts(visibleContacts);

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            key: const PageStorageKey('contacts-tab'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _ContactsTools(
                    importing: _importing,
                    onImport: _importContacts,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                sliver: SliverToBoxAdapter(child: _buildSearchField()),
              ),
              if (_activeCampaign != null &&
                  _activeCampaign!.scheduledCampaignId == null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _CampaignStatusCard(
                      campaign: _activeCampaign!,
                      state: _campaignState ?? CampaignState.queued,
                      currentContact: _currentContact,
                      onCancel: _cancelCampaign,
                    ),
                  ),
                ),
              if (_selectionMode)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _SelectionBar(
                      count: _selectedIds.length,
                      allVisibleSelected:
                          visibleContacts.isNotEmpty &&
                          visibleContacts.every(
                            (contact) => _selectedIds.contains(contact.id),
                          ),
                      onClear: () => setState(_selectedIds.clear),
                      onSelectAll: () => _selectAllVisible(visibleContacts),
                      onSend: () => _composeFor(
                        _contacts
                            .where(
                              (contact) => _selectedIds.contains(contact.id),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 9),
                sliver: SliverToBoxAdapter(
                  child: _SectionHeading(
                    title: 'مخاطبان',
                    detail: _query.isEmpty
                        ? '${_contacts.length} مخاطب ذخیره‌شده'
                        : '${visibleContacts.length} نتیجه جست‌وجو',
                  ),
                ),
              ),
              if (visibleContacts.isEmpty)
                SliverToBoxAdapter(
                  child: _EmptyContacts(
                    searching: _query.isNotEmpty,
                    onAdd: _addContact,
                  ),
                ),
              for (final group in groups) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 5, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Builder(
                      builder: (context) {
                        final allOnDay = _contactsOnDay(group.day);
                        final selectedCount = allOnDay
                            .where(
                              (contact) => _selectedIds.contains(contact.id),
                            )
                            .length;
                        return _ContactDateHeader(
                          day: group.day,
                          visibleCount: group.contacts.length,
                          totalCount: allOnDay.length,
                          selected: selectedCount == 0
                              ? false
                              : selectedCount == allOnDay.length
                              ? true
                              : null,
                          onToggle: () => _toggleDaySelection(group.day),
                        );
                      },
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: group.contacts.length,
                    itemBuilder: (context, index) {
                      final contact = group.contacts[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ContactCard(
                          contact: contact,
                          selectionMode: _selectionMode,
                          selected: _selectedIds.contains(contact.id),
                          onTap: () => _selectionMode
                              ? _toggleSelection(contact)
                              : _composeFor([contact]),
                          onLongPress: () => _toggleSelection(contact),
                          onAction: (action) {
                            switch (action) {
                              case _ContactAction.edit:
                                unawaited(_editContact(contact));
                              case _ContactAction.delete:
                                unawaited(_deleteContact(contact));
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
        if (!_selectionMode)
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'add-contact',
              onPressed: _addContact,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('مخاطب جدید'),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'جست‌وجوی نام یا شماره موبایل',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'پاک کردن جست‌وجو',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
      onChanged: (value) => setState(() => _query = value),
    );
  }
}

class _ContactGroup {
  const _ContactGroup({required this.day, required this.contacts});

  final DateTime day;
  final List<Contact> contacts;
}

bool _sameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

class _ContactsTools extends StatelessWidget {
  const _ContactsTools({required this.importing, required this.onImport});

  final bool importing;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: importing ? null : onImport,
      icon: importing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_file_rounded),
      label: Text(importing ? 'در حال خواندن…' : 'ورود مخاطب از XLSX / CSV'),
    );
  }
}

class _ContactDateHeader extends StatelessWidget {
  const _ContactDateHeader({
    required this.day,
    required this.visibleCount,
    required this.totalCount,
    required this.selected,
    required this.onToggle,
  });

  final DateTime day;
  final int visibleCount;
  final int totalCount;
  final bool? selected;
  final VoidCallback onToggle;

  String _label(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_sameDay(day, today)) return 'امروز';
    if (_sameDay(day, today.subtract(const Duration(days: 1)))) return 'دیروز';
    return MaterialLocalizations.of(context).formatFullDate(day);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = visibleCount != totalCount;
    return Material(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(6, 5, 12, 5),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                tristate: true,
                onChanged: (_) => onToggle(),
              ),
              const Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _label(context),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                filtered
                    ? '$visibleCount از $totalCount مخاطب'
                    : '$totalCount مخاطب',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampaignStatusCard extends StatelessWidget {
  const _CampaignStatusCard({
    required this.campaign,
    required this.state,
    required this.currentContact,
    required this.onCancel,
  });

  final SmsCampaign campaign;
  final CampaignState state;
  final String? currentContact;
  final VoidCallback onCancel;

  String get _statusText => switch (state) {
    CampaignState.waiting => 'منتظر ساعت شروع',
    CampaignState.sending =>
      currentContact == null
          ? 'در حال ارسال'
          : 'در حال ارسال برای $currentContact',
    _ => 'در حال آماده‌سازی',
  };

  @override
  Widget build(BuildContext context) {
    final progress = campaign.totalCount == 0
        ? 0.0
        : campaign.nextIndex / campaign.totalCount;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.14),
            AppColors.surfaceRaised,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_rounded, color: AppColors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${campaign.nextIndex} از ${campaign.totalCount} بررسی شده · ${campaign.sentCount} موفق',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('توقف'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: AppColors.border,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.allVisibleSelected,
    required this.onClear,
    required this.onSelectAll,
    required this.onSend,
  });

  final int count;
  final bool allVisibleSelected;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'لغو انتخاب',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              '$count مخاطب انتخاب شده',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: onSelectAll,
            child: Text(allVisibleSelected ? 'لغو همه' : 'انتخاب همه'),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: onSend,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('پیام'),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
  });

  final Contact contact;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<_ContactAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.10)
          : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
          child: Row(
            children: [
              if (selectionMode)
                Checkbox(value: selected, onChanged: (_) => onTap())
              else
                CircleAvatar(
                  radius: 23,
                  backgroundColor: AppColors.secondary.withValues(alpha: 0.14),
                  foregroundColor: AppColors.secondary,
                  child: Text(
                    contact.initials,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contact.phone,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (contact.note.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        contact.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!selectionMode)
                PopupMenuButton<_ContactAction>(
                  tooltip: 'گزینه‌های مخاطب',
                  onSelected: onAction,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _ContactAction.edit,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('ویرایش'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ContactAction.delete,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.error,
                        ),
                        title: Text('حذف'),
                      ),
                    ),
                  ],
                )
              else
                const Icon(
                  Icons.drag_indicator_rounded,
                  color: AppColors.border,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          detail,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts({required this.searching, required this.onAdd});

  final bool searching;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(
              searching
                  ? Icons.person_search_rounded
                  : Icons.people_outline_rounded,
              color: AppColors.textSecondary,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              searching ? 'مخاطبی پیدا نشد' : 'هنوز مخاطبی ندارید',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              searching
                  ? 'نام یا شماره دیگری را جست‌وجو کنید.'
                  : 'مخاطب را دستی یا از فایل Excel و CSV اضافه کنید.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!searching) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('افزودن مخاطب'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
