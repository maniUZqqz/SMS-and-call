package com.amirali.smsbridge;

import android.Manifest;
import android.app.Activity;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.OpenableColumns;
import android.provider.Settings;
import android.telephony.SmsManager;
import android.telephony.SubscriptionInfo;
import android.telephony.SubscriptionManager;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * پل بومی: ارسال پیامک با انتخاب سیم‌کارت، لیست سیم‌کارت‌ها، وضعیت مجوزها و wake lock.
 * عملیات پیامک فقط از Application Context استفاده می‌کند. انتخاب فایل در engine
 * رابط کاربری و با Activity انجام می‌شود.
 *
 * کدهای نتیجه ارسال:
 *  0 موفق · مقادیر مثبت = SmsManager.RESULT_* · -100 timeout · -101 سیم فعال نیست
 *  -102 استثنا · -103 مجوز ندارد · -104 قابلیت تلفن ندارد · -105 ورودی خالی
 */
public class SmsBridgePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler,
        ActivityAware, PluginRegistry.ActivityResultListener {

    private static final String CHANNEL = "sms_bridge";
    private static final long SEND_TIMEOUT_MS = 60_000L;
    private static final int PICK_CONTACT_FILE_REQUEST = 7431;
    private static final AtomicInteger REQUEST_COUNTER = new AtomicInteger(1);

    private Context context;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private MethodChannel channel;
    private MethodChannel.Result pendingFileResult;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private PowerManager.WakeLock wakeLock;
    private WifiManager.WifiLock wifiLock;

    // ───────────────────────── lifecycle ─────────────────────────

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
        releaseLocks();
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activityBinding = binding;
        activity = binding.getActivity();
        binding.addActivityResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
    }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeActivityResultListener(this);
        }
        activityBinding = null;
        activity = null;
        if (pendingFileResult != null) {
            pendingFileResult.error("NO_ACTIVITY", "صفحه انتخاب فایل بسته شد.", null);
            pendingFileResult = null;
        }
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "filesDir":
                    result.success(context.getFilesDir().getAbsolutePath());
                    break;
                case "status":
                    result.success(status());
                    break;
                case "getSimCards":
                    result.success(simCards());
                    break;
                case "sendSms":
                    sendSms(call, result);
                    break;
                case "pickContactFile":
                    pickContactFile(result);
                    break;
                case "acquireLocks":
                    acquireLocks();
                    result.success(true);
                    break;
                case "releaseLocks":
                    releaseLocks();
                    result.success(true);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Throwable t) {
            result.error("NATIVE_ERROR", t.toString(), null);
        }
    }

    private void pickContactFile(MethodChannel.Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "برای انتخاب فایل باید برنامه باز باشد.", null);
            return;
        }
        if (pendingFileResult != null) {
            result.error("PICKER_BUSY", "یک انتخاب فایل دیگر در حال انجام است.", null);
            return;
        }

        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "text/csv",
                "text/comma-separated-values",
                "application/csv"
        });

        pendingFileResult = result;
        try {
            activity.startActivityForResult(intent, PICK_CONTACT_FILE_REQUEST);
        } catch (Throwable error) {
            pendingFileResult = null;
            result.error("PICKER_ERROR", error.toString(), null);
        }
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != PICK_CONTACT_FILE_REQUEST) return false;

        final MethodChannel.Result result = pendingFileResult;
        pendingFileResult = null;
        if (result == null) return true;
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            result.success(null);
            return true;
        }

        final Uri uri = data.getData();
        new Thread(() -> copyPickedContactFile(uri, result), "contact-file-copy").start();
        return true;
    }

    private void copyPickedContactFile(Uri uri, MethodChannel.Result result) {
        File output = null;
        try {
            String displayName = displayName(uri);
            String extension = extensionOf(displayName);
            if (extension.isEmpty()) {
                String mime = context.getContentResolver().getType(uri);
                extension = mime != null && mime.contains("sheet") ? "xlsx" : "csv";
            }
            if (!("xlsx".equals(extension) || "csv".equals(extension))) {
                throw new IllegalArgumentException("فقط فایل XLSX یا CSV قابل قبول است.");
            }

            output = new File(
                    context.getCacheDir(),
                    "contact-import-" + System.currentTimeMillis() + "." + extension
            );
            try (InputStream input = context.getContentResolver().openInputStream(uri);
                 FileOutputStream sink = new FileOutputStream(output)) {
                if (input == null) throw new IllegalStateException("فایل قابل خواندن نیست.");
                byte[] buffer = new byte[64 * 1024];
                int count;
                while ((count = input.read(buffer)) >= 0) {
                    if (count > 0) sink.write(buffer, 0, count);
                }
                sink.flush();
            }

            Map<String, Object> picked = new HashMap<>();
            picked.put("path", output.getAbsolutePath());
            picked.put("name", displayName.isEmpty() ? output.getName() : displayName);
            mainHandler.post(() -> result.success(picked));
        } catch (Throwable error) {
            if (output != null) output.delete();
            mainHandler.post(() -> result.error("FILE_READ_ERROR", error.getMessage(), null));
        }
    }

    private String displayName(Uri uri) {
        try (Cursor cursor = context.getContentResolver().query(
                uri,
                new String[]{OpenableColumns.DISPLAY_NAME},
                null,
                null,
                null
        )) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) return str(cursor.getString(index));
            }
        } catch (Throwable ignored) {
        }
        return str(uri.getLastPathSegment());
    }

    private String extensionOf(String name) {
        int index = name.lastIndexOf('.');
        if (index < 0 || index == name.length() - 1) return "";
        return name.substring(index + 1).toLowerCase();
    }

    // ───────────────────────── helpers ─────────────────────────

    private boolean has(String permission) {
        return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
    }

    private static String str(CharSequence c) {
        return c == null ? "" : c.toString();
    }

    private Map<String, Object> status() {
        Map<String, Object> m = new HashMap<>();
        m.put("sendSms", has(Manifest.permission.SEND_SMS));
        m.put("phoneState", has(Manifest.permission.READ_PHONE_STATE));
        m.put("phoneNumbers", Build.VERSION.SDK_INT < 26 || has(Manifest.permission.READ_PHONE_NUMBERS));
        m.put("notifications", notificationsEnabled());
        m.put("battery", ignoringBatteryOptimizations());
        m.put("airplane", airplaneMode());
        m.put("telephony", context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_TELEPHONY));
        m.put("sdk", Build.VERSION.SDK_INT);
        m.put("manufacturer", str(Build.MANUFACTURER));
        m.put("model", str(Build.MODEL));
        return m;
    }

    private boolean notificationsEnabled() {
        try {
            NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
            return nm == null || nm.areNotificationsEnabled();
        } catch (Throwable t) {
            return true;
        }
    }

    private boolean ignoringBatteryOptimizations() {
        try {
            PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
            return pm != null && pm.isIgnoringBatteryOptimizations(context.getPackageName());
        } catch (Throwable t) {
            return false;
        }
    }

    private boolean airplaneMode() {
        try {
            return Settings.Global.getInt(context.getContentResolver(), Settings.Global.AIRPLANE_MODE_ON, 0) != 0;
        } catch (Throwable t) {
            return false;
        }
    }

    // ───────────────────────── SIM list ─────────────────────────

    @SuppressWarnings("deprecation")
    private String numberOf(SubscriptionInfo info) {
        try {
            return str(info.getNumber());
        } catch (Throwable t) {
            return "";
        }
    }

    private Map<String, Object> simCards() {
        Map<String, Object> out = new HashMap<>();
        boolean permission = has(Manifest.permission.READ_PHONE_STATE);
        List<Map<String, Object>> list = new ArrayList<>();

        int defaultSub = -1;
        try {
            defaultSub = SubscriptionManager.getDefaultSmsSubscriptionId();
        } catch (Throwable ignored) {
        }

        if (permission) {
            try {
                SubscriptionManager sm =
                        (SubscriptionManager) context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE);
                List<SubscriptionInfo> infos = sm == null ? null : sm.getActiveSubscriptionInfoList();
                if (infos != null) {
                    List<SubscriptionInfo> sorted = new ArrayList<>(infos);
                    Collections.sort(sorted, new Comparator<SubscriptionInfo>() {
                        @Override
                        public int compare(SubscriptionInfo a, SubscriptionInfo b) {
                            return Integer.compare(a.getSimSlotIndex(), b.getSimSlotIndex());
                        }
                    });
                    for (SubscriptionInfo i : sorted) {
                        Map<String, Object> s = new HashMap<>();
                        s.put("subId", i.getSubscriptionId());
                        s.put("slot", i.getSimSlotIndex());
                        s.put("name", str(i.getDisplayName()));
                        s.put("carrier", str(i.getCarrierName()));
                        s.put("number", numberOf(i));
                        s.put("country", str(i.getCountryIso()));
                        s.put("embedded", Build.VERSION.SDK_INT >= 28 && i.isEmbedded());
                        list.add(s);
                    }
                }
            } catch (SecurityException e) {
                permission = false;
            }
        }

        out.put("permission", permission);
        out.put("sims", list);
        out.put("defaultSmsSubId", defaultSub);
        return out;
    }

    private boolean isSubscriptionActive(int subId) {
        try {
            SubscriptionManager sm =
                    (SubscriptionManager) context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE);
            if (sm == null) return true;
            List<SubscriptionInfo> list = sm.getActiveSubscriptionInfoList();
            if (list == null) return false;
            for (SubscriptionInfo i : list) {
                if (i.getSubscriptionId() == subId) return true;
            }
            return false;
        } catch (SecurityException e) {
            return true; // نمی‌توان بررسی کرد؛ اجازه بده خود ارسال نتیجه را بگوید
        }
    }

    // ───────────────────────── send SMS ─────────────────────────

    private Map<String, Object> failure(int code, String error, int subId) {
        Map<String, Object> m = new HashMap<>();
        m.put("ok", false);
        m.put("code", code);
        m.put("parts", 0);
        m.put("partsOk", 0);
        m.put("subId", subId);
        m.put("usedSubId", subId);
        m.put("modemCode", -1);
        m.put("error", error);
        return m;
    }

    @SuppressWarnings("deprecation")
    private SmsManager smsManagerFor(int subId) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            SmsManager base = context.getSystemService(SmsManager.class);
            if (subId >= 0 && base != null) return base.createForSubscriptionId(subId);
            return base != null ? base : SmsManager.getDefault();
        }
        return subId >= 0 ? SmsManager.getSmsManagerForSubscriptionId(subId) : SmsManager.getDefault();
    }

    private PendingIntent sentIntent(int requestCode, Intent intent) {
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                // mutable تا کد خطای مودم (errorCode) هم برگردد؛ intent صریح است (package ست شده)
                return PendingIntent.getBroadcast(context, requestCode, intent, flags | PendingIntent.FLAG_MUTABLE);
            } catch (Throwable t) {
                return PendingIntent.getBroadcast(context, requestCode, intent, flags | PendingIntent.FLAG_IMMUTABLE);
            }
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags);
    }

    /** جمع‌کننده‌ی گزارش «ارسال» برای همه‌ی بخش‌های یک پیامک */
    private class SendTracker extends BroadcastReceiver {
        final int total;
        final int subId;
        final MethodChannel.Result result;
        int got = 0;
        int ok = 0;
        int firstCode = 0;
        int modem = -1;
        boolean done = false;
        Runnable timeout;

        SendTracker(int total, int subId, MethodChannel.Result result) {
            this.total = total;
            this.subId = subId;
            this.result = result;
        }

        @Override
        public void onReceive(Context c, Intent intent) {
            int code = getResultCode();
            got++;
            if (code == Activity.RESULT_OK) {
                ok++;
            } else if (firstCode == 0) {
                firstCode = code;
                try {
                    modem = intent.getIntExtra("errorCode", -1);
                } catch (Throwable ignored) {
                }
            }
            if (got >= total) finish(false);
        }

        void finish(boolean timedOut) {
            if (done) return;
            done = true;
            if (timeout != null) mainHandler.removeCallbacks(timeout);
            try {
                context.unregisterReceiver(this);
            } catch (Throwable ignored) {
            }

            boolean success = !timedOut && ok == total && firstCode == 0;
            Map<String, Object> m = new HashMap<>();
            m.put("ok", success);
            m.put("code", success ? 0 : (timedOut && got < total ? -100 : firstCode));
            m.put("parts", total);
            m.put("partsOk", ok);
            m.put("subId", subId);
            m.put("usedSubId", subId >= 0 ? subId : defaultSub());
            m.put("modemCode", modem);
            m.put("error", success ? "" : (timedOut ? "timeout waiting for sent report" : ""));
            result.success(m);
        }
    }

    private int defaultSub() {
        try {
            return SubscriptionManager.getDefaultSmsSubscriptionId();
        } catch (Throwable t) {
            return -1;
        }
    }

    private void sendSms(MethodCall call, final MethodChannel.Result result) {
        final String to = call.argument("to");
        final String message = call.argument("message");
        Integer subArg = call.argument("subId");
        final int subId = subArg == null ? -1 : subArg;

        if (to == null || to.trim().isEmpty() || message == null || message.isEmpty()) {
            result.success(failure(-105, "destination or message is empty", subId));
            return;
        }
        if (!context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) {
            result.success(failure(-104, "device has no telephony feature", subId));
            return;
        }
        if (!has(Manifest.permission.SEND_SMS)) {
            result.success(failure(-103, "SEND_SMS permission is not granted", subId));
            return;
        }
        if (subId >= 0 && has(Manifest.permission.READ_PHONE_STATE) && !isSubscriptionActive(subId)) {
            result.success(failure(-101, "subscription " + subId + " is not active", subId));
            return;
        }

        final int reqId = REQUEST_COUNTER.getAndIncrement();
        final String action = context.getPackageName() + ".SMS_BRIDGE_SENT_" + reqId;
        SendTracker tracker = null;
        boolean registered = false;

        try {
            SmsManager sm = smsManagerFor(subId);
            if (sm == null) {
                result.success(failure(-102, "SmsManager is null", subId));
                return;
            }

            ArrayList<String> parts = sm.divideMessage(message);
            int total = parts.size();

            tracker = new SendTracker(total, subId, result);
            IntentFilter filter = new IntentFilter(action);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(tracker, filter, Context.RECEIVER_NOT_EXPORTED);
            } else {
                context.registerReceiver(tracker, filter);
            }
            registered = true;

            final SendTracker t = tracker;
            tracker.timeout = new Runnable() {
                @Override
                public void run() {
                    t.finish(true);
                }
            };
            mainHandler.postDelayed(tracker.timeout, SEND_TIMEOUT_MS);

            ArrayList<PendingIntent> sentList = new ArrayList<>();
            for (int p = 0; p < total; p++) {
                Intent in = new Intent(action).setPackage(context.getPackageName());
                sentList.add(sentIntent((reqId * 64 + p) & 0x7fffffff, in));
            }

            if (total == 1) {
                sm.sendTextMessage(to, null, message, sentList.get(0), null);
            } else {
                sm.sendMultipartTextMessage(to, null, parts, sentList, null);
            }
            // نتیجه از طریق SendTracker برمی‌گردد
        } catch (Throwable t) {
            if (registered && tracker != null) {
                tracker.done = true;
                if (tracker.timeout != null) mainHandler.removeCallbacks(tracker.timeout);
                try {
                    context.unregisterReceiver(tracker);
                } catch (Throwable ignored) {
                }
            }
            result.success(failure(-102, t.getClass().getSimpleName() + ": " + t.getMessage(), subId));
        }
    }

    // ───────────────────────── wake / wifi locks ─────────────────────────

    @SuppressWarnings("deprecation")
    private void acquireLocks() {
        try {
            if (wakeLock == null) {
                PowerManager pm = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
                if (pm != null) {
                    wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "smsgateway:poll");
                    wakeLock.setReferenceCounted(false);
                }
            }
            if (wakeLock != null && !wakeLock.isHeld()) wakeLock.acquire();
        } catch (Throwable ignored) {
        }
        try {
            if (wifiLock == null) {
                WifiManager wm = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
                if (wm != null) {
                    int mode = Build.VERSION.SDK_INT >= 34
                            ? WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                            : WifiManager.WIFI_MODE_FULL_HIGH_PERF;
                    wifiLock = wm.createWifiLock(mode, "smsgateway:wifi");
                    wifiLock.setReferenceCounted(false);
                }
            }
            if (wifiLock != null && !wifiLock.isHeld()) wifiLock.acquire();
        } catch (Throwable ignored) {
        }
    }

    private void releaseLocks() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        } catch (Throwable ignored) {
        }
        try {
            if (wifiLock != null && wifiLock.isHeld()) wifiLock.release();
        } catch (Throwable ignored) {
        }
    }
}
