import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:untitled3/core/constants/app_constants.dart';
import 'package:untitled3/core/storage/app_storage.dart';
import 'package:untitled3/core/theme/app_theme.dart';
import 'package:untitled3/features/campaigns/data/scheduled_campaign_storage.dart';
import 'package:untitled3/features/campaigns/presentation/campaigns_tab.dart';
import 'package:untitled3/features/contacts/presentation/contacts_tab.dart';
import 'package:untitled3/features/home/presentation/pages/activity_tab.dart';
import 'package:untitled3/features/home/presentation/pages/dashboard_tab.dart';
import 'package:untitled3/features/home/presentation/pages/settings_tab.dart';
import 'package:untitled3/features/logs/data/log_storage.dart';
import 'package:untitled3/features/logs/domain/log_entry.dart';
import 'package:untitled3/features/settings/domain/server_config.dart';
import 'package:untitled3/features/settings/presentation/permissions_sheet.dart';
import 'package:untitled3/features/settings/presentation/server_settings_sheet.dart';
import 'package:untitled3/features/settings/presentation/sms_settings_sheet.dart';

class _ConnView {
  final String label;
  final String? sub;
  final Color color;
  final IconData icon;

  const _ConnView(this.label, this.sub, this.color, this.icon);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final List<LogEntry> _logs = [];
  final Set<int> _expanded = <int>{};

  LogFilter _filter = LogFilter.all;
  int _selectedTab = 0;

  StreamSubscription<Map<String, dynamic>?>? _subLog;
  StreamSubscription<Map<String, dynamic>?>? _subStatus;

  BridgeStatus _bs = BridgeStatus.unknown;
  bool _running = false;
  bool _userStopped = false;

  ServerConfig _config = ServerConfig.defaults();

  String _conn = 'init';
  int? _latency;
  int _sent = 0;
  int _failed = 0;
  int _polls = 0;
  int _failures = 0;
  DateTime? _lastOk;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    final service = FlutterBackgroundService();

    _subLog = service.on('update').listen(_onLogEvent);
    _subStatus = service.on('status').listen(_onStatusEvent);

    _loadConfig();
    _loadLogs();
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResume();
    }
  }

  Future<void> _onResume() async {
    await _refreshPermissions();
    await _refreshState();
    unawaited(_loadLogs());
    unawaited(_loadConfig());

    // اگر سیستم/سازنده‌ی گوشی سرویس را کشته و کاربر خودش توقف نداده، دوباره بالا بیاور
    if (_bs.sendSms && !_running && !_userStopped) {
      await _startService();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _subLog?.cancel();
    _subStatus?.cancel();

    super.dispose();
  }

  void _onLogEvent(Map<String, dynamic>? event) {
    if (event == null || !mounted) return;

    final raw = event['entry'];

    if (raw is! Map) return;

    try {
      _upsert(LogEntry.fromJson(Map<String, dynamic>.from(raw)));
    } catch (_) {}
  }

  void _onStatusEvent(Map<String, dynamic>? e) {
    if (e == null || !mounted) return;

    final lastOk = e['lastOk'];

    setState(() {
      _conn = e['conn']?.toString() ?? 'init';
      _latency = (e['latency'] as num?)?.toInt();
      _polls = (e['polls'] as num?)?.toInt() ?? _polls;
      _sent = (e['sent'] as num?)?.toInt() ?? _sent;
      _failed = (e['failed'] as num?)?.toInt() ?? _failed;
      _failures = (e['failures'] as num?)?.toInt() ?? 0;
      _lastOk = lastOk is int
          ? DateTime.fromMillisecondsSinceEpoch(lastOk)
          : null;
    });
  }

  void _upsert(LogEntry e) {
    if (!mounted) return;

    setState(() {
      final i = _logs.indexWhere((x) => x.id == e.id);

      if (i >= 0) {
        _logs[i] = e;
      } else {
        _logs.add(e);

        _logs.sort((a, b) => b.id.compareTo(a.id));

        if (_logs.length > kMaxLogs) {
          _logs.removeRange(kMaxLogs, _logs.length);
        }
      }
    });
  }

  void _addLocal(LogEntry e) {
    if (!mounted) return;

    final top = _logs.isNotEmpty ? _logs.first : null;

    if (e.dedupeKey != null && top != null && top.dedupeKey == e.dedupeKey) {
      setState(() {
        top.count++;
        top.time = DateTime.now();
      });

      return;
    }

    _upsert(e);
  }

  Future<void> _loadLogs() async {
    final disk = await LogStorage.load();
    final running = await FlutterBackgroundService().isRunning();

    if (!running) {
      LogStorage.closeStale(disk);
    }

    if (!mounted) return;

    setState(() {
      for (final d in disk) {
        final i = _logs.indexWhere((x) => x.id == d.id);

        if (i < 0) {
          _logs.add(d);
        } else if (d.time.isAfter(_logs[i].time)) {
          _logs[i] = d;
        }
      }

      _logs.sort((a, b) => b.id.compareTo(a.id));

      if (_logs.length > kMaxLogs) {
        _logs.removeRange(kMaxLogs, _logs.length);
      }
    });
  }

  Future<void> _clearLogs() async {
    setState(() {
      _logs.clear();
      _expanded.clear();
    });

    await LogStorage.clear();

    FlutterBackgroundService().invoke('clearLogs');

    _snack('گزارش پاک شد');
  }

  String _exportText() {
    final b = StringBuffer();

    b.writeln('SMS Gateway — ${DateTime.now()}');

    b.writeln(
      'Server: ${_config.baseUrl}  (${_config.otpPath} , ${_config.markSentPath})',
    );

    b.writeln(
      'SIM: ${_config.simTitle} · Template: ${_config.smsTemplate.replaceAll('\n', ' ')}',
    );

    b.writeln(
      'Device: ${_bs.manufacturer} ${_bs.model} · API ${_bs.sdk} · '
      'perms[sms=${_bs.sendSms}, phone=${_bs.phoneState}, notif=${_bs.notifications}, battery=${_bs.battery}]',
    );

    b.writeln('Sent: $_sent | Errors: $_failed | Polls: $_polls');

    b.writeln('─' * 32);

    for (final e in _logs.reversed) {
      b.writeln(e.toPlainText());
    }

    return b.toString();
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _exportText()));

    _snack('کل گزارش کپی شد');
  }

  Future<void> _copyOne(LogEntry e) async {
    await Clipboard.setData(ClipboardData(text: e.toPlainText()));

    _snack('این مورد کپی شد');
  }

  void _snack(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  // ── app state ──────────────────────────────────────────────────────────────

  Future<void> _loadConfig() async {
    final cfg = await ConfigStorage.load();

    if (!mounted) return;

    setState(() => _config = cfg);
  }

  Future<void> _init() async {
    await _requestPermissions();
    await _refreshState();

    if (_bs.sendSms) {
      await _startService();
    }
  }

  Future<void> _refreshPermissions() async {
    final s = await SmsBridge.status();

    if (!mounted) return;

    setState(() => _bs = s);
  }

  /// درخواست همه‌ی مجوزها. [battery] فقط روی اقدام صریح کاربر درخواست می‌شود.
  Future<void> _requestPermissions({bool battery = false}) async {
    try {
      await [
        Permission.sms,
        Permission.phone,
        Permission.notification,
      ].request();
    } catch (_) {}

    if (battery) {
      try {
        if (!await Permission.ignoreBatteryOptimizations.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      } catch (_) {}
    }

    await _refreshPermissions();
    await _logPermissionState();
  }

  Future<void> _logPermissionState() async {
    final s = _bs;

    if (!s.available) {
      _addLocal(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.error,
          title: 'افزونه بومی پیامک در دسترس نیست',
          hint: 'پروژه را flutter clean کنید و دوباره build بگیرید.',
          dedupeKey: 'perm-plugin',
        ),
      );
      return;
    }

    if (!s.sendSms) {
      _addLocal(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.error,
          title: 'مجوز ارسال پیامک داده نشده',
          hint:
              'بدون این مجوز هیچ پیامکی ارسال نمی‌شود. روی «بررسی مجوزها» بزنید.',
          dedupeKey: 'perm-sms',
        ),
      );
    }

    if (!s.phoneState) {
      _addLocal(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.warning,
          title: 'دسترسی به سیم‌کارت‌ها داده نشده',
          hint:
              'بدون مجوز «تلفن» نمی‌توانید سیم‌کارت را انتخاب کنید؛ از پیش‌فرض گوشی استفاده می‌شود.',
          dedupeKey: 'perm-phone',
        ),
      );
    }

    if (!s.notifications) {
      _addLocal(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.warning,
          title: 'مجوز اعلان داده نشده',
          hint: 'بدون اعلان، اندروید ممکن است سرویس پس‌زمینه را متوقف کند.',
          dedupeKey: 'perm-notif',
        ),
      );
    }

    if (!s.battery) {
      _addLocal(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.warning,
          title: 'بهینه‌سازی باتری فعال است',
          hint:
              'ممکن است اندروید سرویس را در پس‌زمینه متوقف کند؛ برنامه را از بهینه‌سازی باتری خارج کنید.',
          dedupeKey: 'perm-battery',
        ),
      );
    }

    if (s.airplane) {
      _addLocal(
        LogEntry(
          kind: LogKind.system,
          level: LogLevel.warning,
          title: 'حالت پرواز روشن است',
          hint: 'تا حالت پرواز روشن است پیامکی ارسال نمی‌شود.',
          dedupeKey: 'perm-airplane',
        ),
      );
    }
  }

  Future<void> _refreshState() async {
    final running = await FlutterBackgroundService().isRunning();

    if (!mounted) return;

    setState(() {
      _running = running;
    });

    if (running) {
      FlutterBackgroundService().invoke('requestStatus');
    }
  }

  Future<void> _startService() async {
    final service = FlutterBackgroundService();

    if (!await service.isRunning()) {
      await service.startService();
    }

    await Future.delayed(const Duration(milliseconds: 500));

    await _refreshState();
  }

  Future<void> _stopService() async {
    final scheduled = await ScheduledCampaignStorage.load();
    final pendingCount = scheduled
        .where((campaign) => !campaign.isTerminal)
        .length;
    if (pendingCount > 0 && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warning,
          ),
          title: const Text('توقف سرویس؟'),
          content: Text(
            '$pendingCount کمپین هنوز در انتظار یا در حال ارسال است. با توقف سرویس، اجرای خودکار تا فعال‌کردن دوباره سرویس متوقف می‌شود.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ادامه فعالیت'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: AppColors.background,
              ),
              child: const Text('توقف سرویس'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _userStopped = true;

    final service = FlutterBackgroundService();

    if (await service.isRunning()) {
      service.invoke('stopService');
    }

    await Future.delayed(const Duration(milliseconds: 700));

    await _refreshState();
  }

  Future<void> _applyConfig(ServerConfig result, String message) async {
    if (!mounted) return;

    setState(() => _config = result);

    await ConfigStorage.save(result);

    FlutterBackgroundService().invoke('updateConfig', result.toJson());

    _snack(message);
  }

  Future<void> _openSettingsSheet() async {
    final result = await showModalBottomSheet<ServerConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ServerSettingsSheet(initialConfig: _config),
    );

    if (result == null || !mounted) return;

    await _applyConfig(result, 'تنظیمات سرور با موفقیت ذخیره شد');
  }

  Future<void> _openSmsSheet() async {
    final result = await showModalBottomSheet<ServerConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SmsSettingsSheet(initialConfig: _config),
    );

    // ممکن است کاربر داخل شیت مجوزی داده باشد
    unawaited(_refreshPermissions());

    if (result == null || !mounted) return;

    await _applyConfig(result, 'تنظیمات پیامک ذخیره شد');
  }

  Future<void> _openPermissionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const PermissionsSheet(),
    );

    await _refreshPermissions();

    if (_bs.sendSms && !_running && !_userStopped) {
      await _startService();
    }
  }

  Future<void> _refreshOverview() async {
    await _refreshPermissions();
    await _refreshState();
    await _loadConfig();
    await _loadLogs();
  }

  Future<void> _startFromUi() async {
    await _ensureSmsReady();
  }

  Future<bool> _ensureSmsReady() async {
    _userStopped = false;
    await _requestPermissions(battery: true);
    if (!_bs.sendSms) {
      await _openPermissionsSheet();
      if (!_bs.sendSms) return false;
    }
    await _startService();
    return _running;
  }

  void _toggleExpanded(int id) {
    setState(() {
      if (!_expanded.add(id)) {
        _expanded.remove(id);
      }
    });
  }

  // ── view helpers ───────────────────────────────────────────────────────────

  int get _missingCount => [
    _bs.sendSms,
    _bs.phoneState,
    _bs.notifications,
    _bs.battery,
  ].where((v) => !v).length;

  _ConnView _connView(ColorScheme cs) {
    const green = AppColors.success;
    const orange = AppColors.warning;

    if (!_running) {
      return const _ConnView(
        'سرویس متوقف است',
        null,
        orange,
        Icons.pause_circle,
      );
    }

    final last = _lastOk != null
        ? 'آخرین اتصال موفق: ${fmtTime(_lastOk!)}'
        : null;

    switch (_conn) {
      case 'ok':
        return _ConnView(
          'متصل به سرور${_latency != null ? ' · ${_latency}ms' : ''}',
          null,
          green,
          Icons.play_circle,
        );

      case 'down':
        return _ConnView(
          'قطع ارتباط با سرور · تلاش $_failures',
          last,
          cs.error,
          Icons.cloud_off_rounded,
        );

      case 'error':
        return _ConnView(
          'سرور خطا برمی‌گرداند · تلاش $_failures',
          last,
          cs.error,
          Icons.error_rounded,
        );

      default:
        return const _ConnView(
          'در حال اتصال به سرور…',
          null,
          orange,
          Icons.sync_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final connection = _connView(colorScheme);
    final issueCount = _logs
        .where(
          (entry) =>
              entry.level == LogLevel.error || entry.level == LogLevel.warning,
        )
        .length;

    const titles = ['داشبورد', 'مخاطب‌ها', 'کمپین‌ها', 'فعالیت‌ها', 'تنظیمات'];
    const subtitles = [
      'وضعیت زنده و کنترل سرویس',
      'مدیریت مخاطبان و ارسال سریع',
      'زمان‌بندی دقیق ارسال‌های مناسبتی',
      'گزارش دریافت و ارسال کدها',
      'سرور، پیامک و دسترسی‌ها',
    ];
    const titleIcons = [
      Icons.space_dashboard_rounded,
      Icons.people_alt_rounded,
      Icons.schedule_send_rounded,
      Icons.receipt_long_rounded,
      Icons.tune_rounded,
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                titleIcons[_selectedTab],
                color: AppColors.background,
                size: 23,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Column(
                  key: ValueKey(_selectedTab),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titles[_selectedTab],
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitles[_selectedTab],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          DashboardTab(
            running: _running,
            connectionLabel: connection.label,
            connectionDetail: connection.sub,
            connectionColor: connection.color,
            connectionIcon: connection.icon,
            sent: _sent,
            failed: _failed,
            polls: _polls,
            nativeBridgeAvailable: _bs.available,
            smsPermissionGranted: _bs.sendSms,
            missingPermissions: _missingCount,
            serverUrl: _config.baseUrl,
            simTitle: _config.simTitle,
            messagePreview: _config.previewMessage,
            latestLog: _logs.isEmpty ? null : _logs.first,
            onRefresh: _refreshOverview,
            onStart: _startFromUi,
            onStop: _stopService,
            onOpenPermissions: _openPermissionsSheet,
            onOpenServer: _openSettingsSheet,
            onOpenSms: _openSmsSheet,
            onOpenActivity: () => setState(() => _selectedTab = 3),
          ),
          ContactsTab(onEnsureReady: _ensureSmsReady),
          CampaignsTab(onEnsureReady: _ensureSmsReady),
          ActivityTab(
            logs: _logs,
            filter: _filter,
            expandedIds: _expanded,
            onFilterChanged: (value) => setState(() => _filter = value),
            onToggleExpanded: _toggleExpanded,
            onCopyOne: _copyOne,
            onCopyAll: _copyAll,
            onClear: _clearLogs,
          ),
          SettingsTab(
            config: _config,
            bridgeStatus: _bs,
            running: _running,
            missingPermissions: _missingCount,
            onOpenServer: _openSettingsSheet,
            onOpenSms: _openSmsSheet,
            onOpenPermissions: _openPermissionsSheet,
            onStart: _startFromUi,
            onStop: _stopService,
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedTab,
          animationDuration: const Duration(milliseconds: 220),
          onDestinationSelected: (index) {
            if (index != _selectedTab) {
              setState(() => _selectedTab = index);
            }
          },
          destinations: [
            NavigationDestination(
              icon: _navIcon(
                Icons.space_dashboard_outlined,
                showDot: !_running,
              ),
              selectedIcon: _navIcon(
                Icons.space_dashboard_rounded,
                showDot: !_running,
              ),
              label: 'داشبورد',
            ),
            NavigationDestination(
              icon: _navIcon(Icons.people_alt_outlined),
              selectedIcon: _navIcon(Icons.people_alt_rounded),
              label: 'مخاطب‌ها',
            ),
            NavigationDestination(
              icon: _navIcon(Icons.event_note_outlined),
              selectedIcon: _navIcon(Icons.schedule_send_rounded),
              label: 'کمپین‌ها',
            ),
            NavigationDestination(
              icon: _navIcon(Icons.receipt_long_outlined, count: issueCount),
              selectedIcon: _navIcon(
                Icons.receipt_long_rounded,
                count: issueCount,
              ),
              label: 'فعالیت‌ها',
            ),
            NavigationDestination(
              icon: _navIcon(Icons.tune_outlined, count: _missingCount),
              selectedIcon: _navIcon(Icons.tune_rounded, count: _missingCount),
              label: 'تنظیمات',
            ),
          ],
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, {int count = 0, bool showDot = false}) {
    return Badge(
      isLabelVisible: count > 0 || showDot,
      label: count > 0 ? Text(count > 99 ? '99+' : '$count') : null,
      smallSize: 8,
      child: Icon(icon),
    );
  }
}
