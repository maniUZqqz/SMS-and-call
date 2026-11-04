import 'dart:convert';
import 'dart:io';

import 'package:untitled3/core/storage/app_storage.dart';
import 'package:untitled3/features/contacts/domain/sms_campaign.dart';

class CampaignStorage {
  static const int maxHistoryItems = 50;

  static Future<File> _activeFile() async {
    return File('${await AppDir.path()}/sms_gateway_active_campaign.json');
  }

  static Future<File> _historyFile() async {
    return File('${await AppDir.path()}/sms_gateway_campaign_history.json');
  }

  static Future<SmsCampaign?> loadActive() async {
    try {
      final file = await _activeFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      return SmsCampaign.fromJson(
        Map<String, dynamic>.from(jsonDecode(content) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveActive(SmsCampaign campaign) async {
    await writeAtomicFile(await _activeFile(), jsonEncode(campaign.toJson()));
  }

  static Future<void> clearActive() async {
    try {
      final file = await _activeFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<List<CampaignHistory>> loadHistory() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final raw = jsonDecode(content);
      if (raw is! List) return [];
      final items = raw
          .whereType<Map>()
          .map(
            (item) => CampaignHistory.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      items.sort((a, b) => b.finishedAt.compareTo(a.finishedAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  static Future<void> addHistory(CampaignHistory history) async {
    final items = await loadHistory();
    items.removeWhere((item) => item.id == history.id);
    items.insert(0, history);
    if (items.length > maxHistoryItems) {
      items.removeRange(maxHistoryItems, items.length);
    }
    await writeAtomicFile(
      await _historyFile(),
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }
}
