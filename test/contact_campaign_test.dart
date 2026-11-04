import 'package:flutter_test/flutter_test.dart';
import 'package:untitled3/features/contacts/domain/contact.dart';
import 'package:untitled3/features/contacts/domain/sms_campaign.dart';

void main() {
  test('contact normalizes Persian digits and round-trips through JSON', () {
    final contact = Contact.create(
      name: '  علی رضایی  ',
      phone: '۰۹۱۲ ۳۴۵ ۶۷۸۹',
      note: ' مشتری ویژه ',
    );

    expect(contact.name, 'علی رضایی');
    expect(contact.phone, '09123456789');
    expect(contact.note, 'مشتری ویژه');
    expect(Contact.fromJson(contact.toJson()).toJson(), contact.toJson());
  });

  test('contact search handles Arabic and Persian letter variants', () {
    const contact = Contact(id: '1', name: 'علی کاظمی', phone: '09123456789');

    expect(contactMatchesSearch(contact, 'علي كا'), isTrue);
    expect(contactMatchesSearch(contact, '۳۴۵۶'), isTrue);
    expect(contactMatchesSearch(contact, 'نامرتبط'), isFalse);
  });

  test('campaign preserves recipients and progress in JSON', () {
    final start = DateTime(2026, 10, 24, 10);
    final campaign = SmsCampaign.create(
      message: 'پیام آزمایشی',
      contacts: const [
        Contact(id: '1', name: 'اول', phone: '09120000001'),
        Contact(id: '2', name: 'دوم', phone: '09120000002'),
      ],
      intervalSeconds: 30,
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
    ).copyWith(nextIndex: 1, sentCount: 1, sentRecipientIds: const ['1']);

    final restored = SmsCampaign.fromJson(campaign.toJson());

    expect(restored.totalCount, 2);
    expect(restored.nextIndex, 1);
    expect(restored.sentCount, 1);
    expect(restored.sentRecipientIds, const ['1']);
    expect(restored.recipients.last.name, 'دوم');
  });

  test('campaign history identifies sent and unattempted recipients', () {
    final start = DateTime(2026, 10, 24, 10);
    final campaign = SmsCampaign.create(
      message: 'پیام',
      contacts: const [
        Contact(id: '1', name: 'ارسال شده', phone: '09120000001'),
        Contact(id: '2', name: 'بدون زمان', phone: '09120000002'),
      ],
      intervalSeconds: 60,
      startsAt: start,
      endsAt: start.add(const Duration(minutes: 1)),
    ).copyWith(nextIndex: 1, sentCount: 1, sentRecipientIds: const ['1']);

    final history = CampaignHistory.fromCampaign(
      campaign,
      CampaignState.windowEnded,
    );
    final restored = CampaignHistory.fromJson(history.toJson());

    expect(restored.sentRecipients.single.name, 'ارسال شده');
    expect(restored.unattemptedRecipients.single.name, 'بدون زمان');
  });

  test('campaign capacity respects interval and time window', () {
    final start = DateTime(2026, 10, 24, 10);

    expect(
      campaignWindowCapacity(
        startsAt: start,
        endsAt: start.add(const Duration(minutes: 2)),
        intervalSeconds: 30,
      ),
      4,
    );
    expect(
      campaignWindowCapacity(
        startsAt: start,
        endsAt: start,
        intervalSeconds: 30,
      ),
      0,
    );
  });
}
