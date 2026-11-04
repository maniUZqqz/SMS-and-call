package com.amirali.smsbridge;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.PowerManager;

/**
 * گیرنده‌ی آلارم‌های بیدارکننده و رویدادهای سیستم (ری‌استارت، تغییر ساعت/منطقه‌ی زمانی).
 *
 * وقتی آلارم می‌رسد: یک قفل CPU موقت می‌گیرد، اگر سرویس پس‌زمینه‌ی برنامه زنده است به
 * آن خبر می‌دهد و اگر فرایند/سرویس مرده است، سرویس را دوباره بالا می‌آورد.
 */
public class WakeReceiver extends BroadcastReceiver {
    private static final long WAKE_HOLD_MS = 2 * 60 * 1000L;

    @Override
    public void onReceive(Context context, Intent intent) {
        final String action = intent == null ? null : intent.getAction();
        if (action == null) return;
        final Context app = context.getApplicationContext();

        if ("com.amirali.smsbridge.ARM_TEST".equals(action)) {
            // فقط برای تست خودکار روی شبیه‌ساز (CI): این گیرنده export نشده و فقط root/خودِ برنامه
            // می‌تواند به آن پیام بدهد. آلارم با همان کدی ثبت می‌شود که کمپین‌ها استفاده می‌کنند.
            long delay = intent.getLongExtra("delayMs", 20_000L);
            String slot = intent.getStringExtra("slot");
            String reason = intent.getStringExtra("reason");
            WakeScheduler.arm(app, slot == null ? "smoke" : slot,
                    System.currentTimeMillis() + delay, reason == null ? "smoketest" : reason);
            return;
        }

        if (WakeScheduler.ACTION_WAKE.equals(action)) {
            String slot = intent.getStringExtra("slot");
            String reason = intent.getStringExtra("reason");
            fire(app, slot == null ? "campaign" : slot, reason == null ? "schedule" : reason);
            return;
        }

        if (Intent.ACTION_BOOT_COMPLETED.equals(action)
                || "android.intent.action.QUICKBOOT_POWERON".equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                || "android.intent.action.LOCKED_BOOT_COMPLETED".equals(action)) {
            // آلارم‌ها با ری‌استارت پاک می‌شوند؛ دوباره ثبت می‌کنیم
            WakeScheduler.rearmAll(app);
            return;
        }

        if (Intent.ACTION_TIMEZONE_CHANGED.equals(action) || Intent.ACTION_TIME_CHANGED.equals(action)) {
            // زمان‌بندی‌ها بر پایه‌ی ساعت محلی است؛ سرویس باید لحظه‌ی بعدی را دوباره حساب کند
            WakeScheduler.rearmAll(app);
            if (!WakeScheduler.pending(app).isEmpty()) fire(app, "campaign", "timechange");
        }
    }

    static void fire(Context app, String slot, String reason) {
        SharedPreferences prefs = WakeScheduler.prefs(app);
        prefs.edit().remove("at_" + slot).remove("reason_" + slot).apply();

        PowerManager.WakeLock hold = null;
        try {
            PowerManager pm = (PowerManager) app.getSystemService(Context.POWER_SERVICE);
            if (pm != null) {
                hold = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "smsandcall:wake");
                hold.acquire(WAKE_HOLD_MS);
            }
        } catch (Throwable ignored) {
        }

        boolean delivered = SmsBridgePlugin.notifyWake(reason);
        StringBuilder error = new StringBuilder();
        boolean started = false;
        if (!delivered) started = WakeScheduler.startService(app, error);

        prefs.edit()
                .putLong("last_fired_at", System.currentTimeMillis())
                .putString("last_fired_reason", reason)
                .putBoolean("last_started_service", delivered || started)
                .putString("last_error", delivered ? "" : error.toString())
                .apply();
        // قفل موقت خودش بعد از WAKE_HOLD_MS آزاد می‌شود (فرصتِ بالا آمدن سرویس و موتور Dart)
    }
}
