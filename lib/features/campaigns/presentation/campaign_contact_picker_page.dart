import 'package:flutter/material.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/contacts/domain/contact.dart';

class CampaignContactPickerPage extends StatefulWidget {
  const CampaignContactPickerPage({
    super.key,
    required this.contacts,
    required this.selectedIds,
  });

  final List<Contact> contacts;
  final Set<String> selectedIds;

  @override
  State<CampaignContactPickerPage> createState() =>
      _CampaignContactPickerPageState();
}

class _CampaignContactPickerPageState extends State<CampaignContactPickerPage> {
  final _searchController = TextEditingController();
  late final Set<String> _selectedIds = Set<String>.from(widget.selectedIds);
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(Contact contact) {
    setState(() {
      if (!_selectedIds.add(contact.id)) _selectedIds.remove(contact.id);
    });
  }

  void _toggleVisible(List<Contact> visible) {
    setState(() {
      final allSelected =
          visible.isNotEmpty &&
          visible.every((contact) => _selectedIds.contains(contact.id));
      if (allSelected) {
        _selectedIds.removeAll(visible.map((contact) => contact.id));
      } else {
        _selectedIds.addAll(visible.map((contact) => contact.id));
      }
    });
  }

  void _submit() {
    Navigator.of(context).pop(
      widget.contacts
          .where((contact) => _selectedIds.contains(contact.id))
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = widget.contacts
        .where((contact) => contactMatchesSearch(contact, _query))
        .toList(growable: false);
    final allVisibleSelected =
        visible.isNotEmpty &&
        visible.every((contact) => _selectedIds.contains(contact.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('انتخاب مخاطبان'),
        actions: [
          TextButton(
            onPressed: visible.isEmpty ? null : () => _toggleVisible(visible),
            child: Text(allVisibleSelected ? 'لغو همه' : 'انتخاب همه'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'جست‌وجوی نام یا شماره موبایل',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'پاک‌کردن جست‌وجو',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Row(
              children: [
                Text(
                  '${_selectedIds.length} انتخاب‌شده',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  '${visible.length} نتیجه',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? _EmptyPicker(searching: _query.trim().isNotEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final contact = visible[index];
                      final selected = _selectedIds.contains(contact.id);
                      return Material(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary.withValues(alpha: 0.45)
                                : AppColors.border,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _toggle(contact),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 21,
                                  backgroundColor: AppColors.secondary
                                      .withValues(alpha: 0.14),
                                  foregroundColor: AppColors.secondary,
                                  child: Text(
                                    contact.initials,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        contact.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        contact.phone,
                                        textDirection: TextDirection.ltr,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Checkbox(
                                  value: selected,
                                  onChanged: (_) => _toggle(contact),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: FilledButton.icon(
          onPressed: _selectedIds.isEmpty ? null : _submit,
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text('تأیید ${_selectedIds.length} مخاطب'),
        ),
      ),
    );
  }
}

class _EmptyPicker extends StatelessWidget {
  const _EmptyPicker({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.person_search_rounded
                  : Icons.people_outline_rounded,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'مخاطبی پیدا نشد' : 'هنوز مخاطبی ثبت نشده است',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}
