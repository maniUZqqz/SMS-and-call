import 'dart:convert';
import 'dart:io';

import 'package:untitled3/core/storage/app_storage.dart';
import 'package:untitled3/features/campaigns/domain/scheduled_campaign.dart';

class ScheduledCampaignStorage {
  static Future<File> _file() async {
    return File('${await AppDir.path()}/sms_gateway_scheduled_campaigns.json');
  }

  static Future<File> _lockFile() async {
    return File('${await AppDir.path()}/sms_gateway_scheduled_campaigns.lock');
  }

  static Future<List<ScheduledCampaign>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final raw = jsonDecode(content);
      if (raw is! List) return [];
      final campaigns = raw
          .whereType<Map>()
          .map(
            (item) =>
                ScheduledCampaign.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((campaign) => campaign.id.isNotEmpty)
          .toList();
      campaigns.sort(_compareCampaigns);
      return campaigns;
    } catch (_) {
      return [];
    }
  }

  static Future<void> upsert(ScheduledCampaign campaign) async {
    await _mutate((campaigns) {
      final index = campaigns.indexWhere((item) => item.id == campaign.id);
      if (index < 0) {
        campaigns.add(campaign);
      } else {
        campaigns[index] = campaign;
      }
    });
  }

  static Future<ScheduledCampaign?> update(
    String id,
    ScheduledCampaign Function(ScheduledCampaign campaign) transform,
  ) async {
    ScheduledCampaign? result;
    await _mutate((campaigns) {
      final index = campaigns.indexWhere((item) => item.id == id);
      if (index < 0) return;
      result = transform(campaigns[index]);
      campaigns[index] = result!;
    });
    return result;
  }

  static Future<void> delete(String id) async {
    await _mutate((campaigns) {
      campaigns.removeWhere((campaign) => campaign.id == id);
    });
  }

  static Future<void> _mutate(
    void Function(List<ScheduledCampaign> campaigns) operation,
  ) async {
    final lockHandle = await (await _lockFile()).open(mode: FileMode.append);
    try {
      await lockHandle.lock(FileLock.exclusive);
      final campaigns = await load();
      operation(campaigns);
      campaigns.sort(_compareCampaigns);
      await writeAtomicFile(
        await _file(),
        jsonEncode(campaigns.map((campaign) => campaign.toJson()).toList()),
      );
    } finally {
      try {
        await lockHandle.unlock();
      } catch (_) {}
      await lockHandle.close();
    }
  }

  static int _compareCampaigns(
    ScheduledCampaign first,
    ScheduledCampaign second,
  ) {
    final firstActive = !first.isTerminal;
    final secondActive = !second.isTerminal;
    if (firstActive != secondActive) return firstActive ? -1 : 1;
    return firstActive
        ? first.startsAt.compareTo(second.startsAt)
        : second.startsAt.compareTo(first.startsAt);
  }
}
