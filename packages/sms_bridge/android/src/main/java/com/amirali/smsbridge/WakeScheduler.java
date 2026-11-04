package com.amirali.smsbridge;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import androidx.core.content.ContextCompat;

import java.util.HashMap;
import java.util.Map;

/**
 * آلارم‌های بیدارکننده‌ی سیستم‌عامل. هر بخش برنامه (کمپین‌ها، ضبط‌ها، آزمایش) یک «slot»
 * جدا دارد. آلارم‌ها با AlarmManager ثبت می‌شوند، پس بعد از کشته‌شدن فرایند، در حالت Doze
 * و (با ثبت دوباره‌ی {@link WakeReceiver}) بعد از ری‌استارت هم کار می‌کنند.
 *
 * زمان آلارم هر slot در SharedPreferences هم نگه داشته می‌شود تا بعد از ری‌استارت گوشی
 * دوباره ثبت شود.
 */
final class WakeScheduler {
    static final String PREFS = "smsbridge_wake";
    static final String ACTION_WAKE = "com.amirali.smsbridge.WAKE";
    static final String SERVICE_CLASS = "id.flutter.flutter_background_service.BackgroundService";
    static final String SERVICE_PREFS = "id.flutter.background_service";

    private WakeScheduler() {
    }

    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static int requestCode(String slot) {
        switch (slot) {
            case "campaign":
                return 7001;
            case "calls":
                return 7002;
            case "call_ended":
                return 7003;
            case "selftest":
                return 7004;
            case "smoke":
                return 7005;
            default:
                return 7100 + (slot.hashCode() & 0x3ff);
        }
    }

    private static PendingIntent pendingFor(Context c, String slot, String reason, int flags) {
        Intent intent = new Intent(ACTION_WAKE);
        intent.setComponent(new ComponentName(c, WakeReceiver.class));
        intent.putExtra("slot", slot);
        intent.putExtra("reason", reason);
        int f = flags;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) f |= PendingIntent.FLAG_IMMUTABLE;
        return PendingIntent.getBroadcast(c, requestCode(slot), intent, f);
    }

    static boolean canScheduleExact(Context c) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true;
        try {
            AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
            return am != null && am.canScheduleExactAlarms();
        } catch (Throwable t) {
            return false;
        }
    }

    /** آلارم slot را ثبت می‌کند (جایگزین قبلی). نتیجه: "exact"، "inexact" یا "failed". */
    static String arm(Context c, String slot, long atMillis, String reason) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return "failed";
        prefs(c).edit()
                .putLong("at_" + slot, atMillis)
                .putString("reason_" + slot, reason)
                .apply();
        PendingIntent pi = pendingFor(c, slot, reason, PendingIntent.FLAG_UPDATE_CURRENT);
        try {
            if (canScheduleExact(c)) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi);
                return "exact";
            }
        } catch (SecurityException ignored) {
            // اجازه‌ی آلارم دقیق در لحظه برداشته شد؛ به آلارم تقریبی برمی‌گردیم
        }
        try {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi);
            return "inexact";
        } catch (Throwable t) {
            return "failed";
        }
    }

    static void cancel(Context c, String slot) {
        prefs(c).edit().remove("at_" + slot).remove("reason_" + slot).apply();
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        try {
            PendingIntent pi = pendingFor(c, slot, "", PendingIntent.FLAG_UPDATE_CURRENT);
            am.cancel(pi);
            pi.cancel();
        } catch (Throwable ignored) {
        }
    }

    /** همه‌ی slotهایی که زمان آلارم دارند: slot ← زمان. */
    static Map<String, Long> pending(Context c) {
        Map<String, Long> result = new HashMap<>();
        for (Map.Entry<String, ?> e : prefs(c).getAll().entrySet()) {
            if (e.getKey().startsWith("at_") && e.getValue() instanceof Long) {
                result.put(e.getKey().substring(3), (Long) e.getValue());
            }
        }
        return result;
    }

    /** بعد از ری‌استارت گوشی، آلارم‌های ذخیره‌شده دوباره ثبت می‌شوند. */
    static void rearmAll(Context c) {
        long now = System.currentTimeMillis();
        for (Map.Entry<String, Long> e : pending(c).entrySet()) {
            String reason = prefs(c).getString("reason_" + e.getKey(), "schedule");
            // آلارم گذشته: چند ثانیه‌ی دیگر (سرویس تازه بالا می‌آید و خودش بررسی می‌کند)
            arm(c, e.getKey(), Math.max(e.getValue(), now + 5_000L), reason);
        }
    }

    /**
     * سرویس پس‌زمینه (flutter_background_service) را بالا می‌آورد. اگر کاربر خودش سرویس
     * را متوقف کرده باشد، بالا نمی‌آید. true یعنی دستور شروع صادر شد.
     */
    static boolean startService(Context c, StringBuilder error) {
        try {
            SharedPreferences cfg = c.getSharedPreferences(SERVICE_PREFS, Context.MODE_PRIVATE);
            if (cfg.getBoolean("is_manually_stopped", false)) {
                error.append("سرویس به‌صورت دستی متوقف شده بود");
                return false;
            }
            Intent intent = new Intent();
            intent.setClassName(c.getPackageName(), SERVICE_CLASS);
            if (cfg.getBoolean("is_foreground", false)) {
                ContextCompat.startForegroundService(c, intent);
            } else {
                c.startService(intent);
            }
            return true;
        } catch (Throwable t) {
            error.append(t.getClass().getSimpleName()).append(": ").append(t.getMessage());
            return false;
        }
    }

    /**
     * قفل CPUِ خودِ افزونه‌ی flutter_background_service (که هرگز آزادش نمی‌کند) را رها می‌کند.
     * بدون این، CPU تا آخر عمر فرایند بیدار می‌ماند و باتری می‌خورد.
     */
    static void releasePluginWakeLock() {
        try {
            Class<?> cls = Class.forName(SERVICE_CLASS);
            java.lang.reflect.Field field = cls.getField("lockStatic");
            Object lock = field.get(null);
            if (lock instanceof android.os.PowerManager.WakeLock) {
                android.os.PowerManager.WakeLock wl = (android.os.PowerManager.WakeLock) lock;
                int guard = 0;
                while (wl.isHeld() && guard++ < 32) wl.release();
            }
        } catch (Throwable ignored) {
        }
    }
}
