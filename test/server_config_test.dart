import 'package:flutter_test/flutter_test.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/features/settings/domain/server_config.dart';

void main() {
  group('ServerConfig', () {
    test('builds endpoint URIs with normalized slashes', () {
      final config = ServerConfig(
        baseUrl: 'http://10.0.0.2:5000/',
        otpPath: 'api/next-otp',
        markSentPath: 'api/mark-sent',
      );

      expect(config.otpUri.toString(), 'http://10.0.0.2:5000/api/next-otp');
      expect(
        config.markSentUri.toString(),
        'http://10.0.0.2:5000/api/mark-sent',
      );
    });

    test('builds messages with and without a code placeholder', () {
      final config = ServerConfig.defaults();

      config.smsTemplate = 'کد: {code}';
      expect(config.buildMessage('123456'), 'کد: 123456');

      config.smsTemplate = 'کد تایید';
      expect(config.buildMessage('123456'), 'کد تایید 123456');

      config.smsTemplate = '';
      expect(config.buildMessage('123456'), '123456');
    });
  });

  group('pickSubId', () {
    final sims = [
      const SimCard(
        subscriptionId: 11,
        slot: 0,
        name: 'SIM 1',
        carrier: 'Carrier A',
        number: '',
        country: 'ir',
        embedded: false,
      ),
      const SimCard(
        subscriptionId: 22,
        slot: 1,
        name: 'SIM 2',
        carrier: 'Carrier B',
        number: '',
        country: 'ir',
        embedded: false,
      ),
    ];

    test('uses the selected active subscription', () {
      final config = ServerConfig.defaults().copyWith(
        simSubscriptionId: 22,
        simSlot: 1,
      );
      final query = SimQuery(
        permissionGranted: true,
        sims: sims,
        defaultSmsSubId: 11,
      );

      expect(pickSubId(config, query), 22);
    });

    test('remaps a changed subscription id by physical slot', () {
      final config = ServerConfig.defaults().copyWith(
        simSubscriptionId: 99,
        simSlot: 1,
      );
      final query = SimQuery(
        permissionGranted: true,
        sims: sims,
        defaultSmsSubId: 11,
      );

      expect(pickSubId(config, query), 22);
    });

    test('uses the first active SIM when no default exists', () {
      final query = SimQuery(
        permissionGranted: true,
        sims: sims,
        defaultSmsSubId: -1,
      );

      expect(pickSubId(ServerConfig.defaults(), query), 11);
    });
  });
}
