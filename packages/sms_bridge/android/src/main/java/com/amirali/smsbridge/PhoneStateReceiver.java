package com.amirali.smsbridge;

import android.Manifest;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.telephony.TelephonyManager;

/**
 * تغییر وضعیت تماس را می‌گیرد (زنگ ← در تماس ← تمام) و دو کار می‌کند:
 *  1. اگر «ضبط‌کننده‌ی داخلی» روشن است و سرویس دسترس‌پذیری فعال، هنگام برقراری تماس ضبط
 *     را شروع و هنگام پایان متوقف می‌کند.
 *  2. چند ثانیه بعد از پایان هر تماس یک آلارم «call_ended» ثبت می‌کند تا برنامه بدون
 *     دخالت کاربر ضبطِ تازه‌ی گوشی را پیدا، به تماس وصل و به متن تبدیل کند.
 * وضعیت تماس در SharedPreferences می‌ماند چون فرایند میان تماس ممکن است بمیرد.
 */
public class PhoneStateReceiver extends BroadcastReceiver {
    private static final String PREFS = "smsbridge_phone_state";
    private static final long AFTER_CALL_DELAY_MS = 25_000L;

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !TelephonyManager.ACTION_PHONE_STATE_CHANGED.equals(intent.getAction())) return;
        final Context app = context.getApplicationContext();
        String state = intent.getStringExtra(TelephonyManager.EXTRA_STATE);
        if (state == null) return;
        SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);

        if (TelephonyManager.EXTRA_STATE_RINGING.equals(state)) {
            @SuppressWarnings("deprecation")
            String number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER);
            SharedPreferences.Editor ringing = prefs.edit().putBoolean("ringing", true);
            // اندروید گاهی اعلان دوم را بدون شماره می‌فرستد؛ شمارهٔ شناخته‌شده را پاک نکن
            if (number != null && !number.isEmpty()) ringing.putString("number", number);
            ringing.apply();
            return;
        }

        if (TelephonyManager.EXTRA_STATE_OFFHOOK.equals(state)) {
            if (prefs.getBoolean("in_call", false)) return; // اعلان تکراری
            boolean incoming = prefs.getBoolean("ringing", false);
            String number = prefs.getString("number", "");
            prefs.edit().putBoolean("in_call", true).putBoolean("ringing", false).apply();
            startRecordingIfEnabled(app, incoming ? "incoming" : "outgoing", number);
            return;
        }

        if (TelephonyManager.EXTRA_STATE_IDLE.equals(state)) {
            boolean wasInCall = prefs.getBoolean("in_call", false);
            prefs.edit().putBoolean("in_call", false).putBoolean("ringing", false)
                    .putString("number", "").apply();
            // فقط ضبطِ همین تماس را ببند؛ ضبط دستیِ کاربر یا یک اعلان IDLE بی‌ربط (تماس بی‌پاسخ) نباید قطعش کند
            if (wasInCall && RecorderEngine.isRecording() && !RecorderEngine.isManual()) {
                RecorderEngine.stop(app);
            }
            if (wasInCall) {
                WakeScheduler.arm(app, "call_ended",
                        System.currentTimeMillis() + AFTER_CALL_DELAY_MS, "call_ended");
            }
        }
    }

    private static void startRecordingIfEnabled(Context app, String direction, String number) {
        SharedPreferences cfg = RecorderEngine.prefs(app);
        if (!cfg.getBoolean("enabled", false)) return;
        if (app.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            cfg.edit().putString("last_error", "مجوز میکروفون داده نشده است.").apply();
            return;
        }
        if (!CallRecorderAccessibilityService.isEnabledInSettings(app)) {
            cfg.edit().putString("last_error",
                    "سرویس دسترس‌پذیری «ضبط تماس» روشن نیست؛ بدون آن اندروید ضبط پس‌زمینه را ساکت می‌کند.").apply();
            return;
        }
        RecorderEngine.start(app, false, direction, number, cfg.getBoolean("auto_speaker", false));
    }
}
