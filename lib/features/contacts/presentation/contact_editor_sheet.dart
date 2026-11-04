import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/contacts/domain/contact.dart';

class ContactEditorSheet extends StatefulWidget {
  const ContactEditorSheet({super.key, this.contact});

  final Contact? contact;

  @override
  State<ContactEditorSheet> createState() => _ContactEditorSheetState();
}

class _ContactEditorSheetState extends State<ContactEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _noteController;

  bool get _isEditing => widget.contact != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.contact?.name);
    _phoneController = TextEditingController(text: widget.contact?.phone);
    _noteController = TextEditingController(text: widget.contact?.note);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final contact =
        widget.contact?.copyWith(
          name: _nameController.text,
          phone: _phoneController.text,
          note: _noteController.text,
        ) ??
        Contact.create(
          name: _nameController.text,
          phone: _phoneController.text,
          note: _noteController.text,
        );
    Navigator.of(context).pop(contact);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing ? 'ویرایش مخاطب' : 'مخاطب جدید',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'اطلاعات فقط در حافظه همین گوشی ذخیره می‌شود',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _nameController,
                autofocus: !_isEditing,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'نام مخاطب',
                  hintText: 'مثلاً علی رضایی',
                  prefixIcon: Icon(Icons.badge_outlined),
                  counterText: '',
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'نام مخاطب را وارد کنید'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9۰-۹٠-٩+()\-\s]'),
                  ),
                ],
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'شماره موبایل',
                  hintText: '09123456789',
                  prefixIcon: Icon(Icons.phone_iphone_rounded),
                  counterText: '',
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'شماره موبایل را وارد کنید';
                  }
                  if (!isValidPhoneNumber(value!)) {
                    return 'شماره موبایل معتبر نیست';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                maxLength: 240,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'توضیحات (اختیاری)',
                  hintText: 'هر یادداشتی که برای شناخت مخاطب لازم است',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 8),
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
                      onPressed: _save,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        _isEditing ? 'ذخیره تغییرات' : 'افزودن مخاطب',
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
