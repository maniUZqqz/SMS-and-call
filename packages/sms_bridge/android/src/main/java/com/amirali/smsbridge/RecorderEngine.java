package com.amirali.smsbridge;

import android.content.Context;
import android.content.SharedPreferences;
import android.media.AudioManager;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/**
 * ضبط‌کننده‌ی داخلی (بهترین تلاش). از میکروفون ضبط می‌کند: اندروید ۱۰ به بعد برنامه‌های
 * عادی اجازه‌ی ضبط مستقیم صدای تماس (VOICE_CALL) ندارند؛ پس فقط صدای میکروفون ضبط می‌شود
 * و صدای طرف مقابل وقتی ضبط می‌شود که از بلندگوی گوشی پخش شود. بعضی گوشی‌ها در زمان تماس
 * میکروفون را از برنامه‌ها می‌گیرند و فایل بی‌صدا می‌شود؛ این حالت با اندازه‌گیری بلندی
 * صدا تشخیص و گزارش می‌شود.
 *
 * فایل‌ها در {@code filesDir/inapp_recordings/} با یک فایل JSON کناری (زمان، جهت، شماره)
 * ذخیره می‌شوند و بخش Dart آن‌ها را وارد برنامه می‌کند.
 */
final class RecorderEngine {
    static final String FOLDER = "inapp_recordings";
    static final String PREFS = "smsbridge_recorder";
    private static final int SILENCE_PEAK = 40;

    private static final Object LOCK = new Object();
    private static MediaRecorder recorder;
    private static File file;
    private static long startedAt;
    private static boolean manual;
    private static String direction = "unknown";
    private static String number = "";
    private static String sourceName = "";
    private static int peak;
    private static boolean speakerForced;
    private static boolean previousSpeaker;
    private static Handler handler;
    private static Runnable meter;

    private RecorderEngine() {
    }

    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static File dir(Context c) {
        File d = new File(c.getFilesDir(), FOLDER);
        if (!d.exists()) d.mkdirs();
        return d;
    }

    static boolean isRecording() {
        synchronized (LOCK) {
            return recorder != null;
        }
    }

    static boolean isManual() {
        synchronized (LOCK) {
            return recorder != null && manual;
        }
    }

    static boolean start(Context context, boolean isManual, String callDirection, String callNumber,
                         boolean autoSpeaker) {
        synchronized (LOCK) {
            if (recorder != null) return true;
            Context app = context.getApplicationContext();
            File out = new File(dir(app), (isManual ? "manual_" : "call_") + System.currentTimeMillis() + ".m4a");

            // اول VOICE_RECOGNITION (معمولاً بدون پردازش‌های حذف نویز)، بعد MIC
            int[] sources = new int[]{MediaRecorder.AudioSource.VOICE_RECOGNITION, MediaRecorder.AudioSource.MIC};
            String[] names = new String[]{"VOICE_RECOGNITION", "MIC"};
            String failure = "";
            for (int i = 0; i < sources.length; i++) {
                MediaRecorder r = null;
                try {
                    r = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                            ? new MediaRecorder(app) : legacyRecorder();
                    r.setAudioSource(sources[i]);
                    r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
                    r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
                    r.setAudioChannels(1);
                    r.setAudioSamplingRate(16000);
                    r.setAudioEncodingBitRate(48000);
                    r.setOutputFile(out.getAbsolutePath());
                    r.prepare();
                    r.start();
                    recorder = r;
                    file = out;
                    startedAt = System.currentTimeMillis();
                    manual = isManual;
                    direction = callDirection == null ? "unknown" : callDirection;
                    number = callNumber == null ? "" : callNumber;
                    sourceName = names[i];
                    peak = 0;
                    break;
                } catch (Throwable t) {
                    failure = t.getClass().getSimpleName() + ": " + t.getMessage();
                    if (r != null) {
                        try {
                            r.release();
                        } catch (Throwable ignored) {
                        }
                    }
                    out.delete();
                }
            }
            if (recorder == null) {
                prefs(app).edit().putString("last_error", "شروع ضبط ممکن نشد: " + failure).apply();
                return false;
            }

            prefs(app).edit().putBoolean("recording", true).apply();
            if (autoSpeaker) forceSpeaker(app);
            startMeter();
            return true;
        }
    }

    @SuppressWarnings("deprecation")
    private static MediaRecorder legacyRecorder() {
        return new MediaRecorder();
    }

    private static void startMeter() {
        if (handler == null) handler = new Handler(Looper.getMainLooper());
        meter = new Runnable() {
            @Override
            public void run() {
                synchronized (LOCK) {
                    if (recorder == null) return;
                    try {
                        peak = Math.max(peak, recorder.getMaxAmplitude());
                    } catch (Throwable ignored) {
                    }
                }
                handler.postDelayed(this, 1000L);
            }
        };
        handler.postDelayed(meter, 1000L);
    }

    @SuppressWarnings("deprecation")
    private static void forceSpeaker(Context app) {
        try {
            AudioManager am = (AudioManager) app.getSystemService(Context.AUDIO_SERVICE);
            if (am == null) return;
            previousSpeaker = am.isSpeakerphoneOn();
            am.setSpeakerphoneOn(true);
            speakerForced = true;
        } catch (Throwable ignored) {
        }
    }

    @SuppressWarnings("deprecation")
    private static void restoreSpeaker(Context app) {
        if (!speakerForced) return;
        try {
            AudioManager am = (AudioManager) app.getSystemService(Context.AUDIO_SERVICE);
            if (am != null) am.setSpeakerphoneOn(previousSpeaker);
        } catch (Throwable ignored) {
        }
        speakerForced = false;
    }

    /** ضبط را تمام می‌کند و فایل JSON کناری را می‌نویسد. true اگر فایلی ذخیره شد. */
    static boolean stop(Context context) {
        synchronized (LOCK) {
            if (recorder == null) return false;
            Context app = context.getApplicationContext();
            if (handler != null && meter != null) handler.removeCallbacks(meter);
            try {
                peak = Math.max(peak, recorder.getMaxAmplitude());
            } catch (Throwable ignored) {
            }
            boolean ok = true;
            try {
                recorder.stop();
            } catch (Throwable t) {
                ok = false; // ضبط خیلی کوتاه بود یا موتور ضبط خراب شد
            }
            try {
                recorder.release();
            } catch (Throwable ignored) {
            }
            recorder = null;
            restoreSpeaker(app);

            long endedAt = System.currentTimeMillis();
            File saved = file;
            file = null;
            SharedPreferences.Editor edit = prefs(app).edit().putBoolean("recording", false);

            if (!ok || saved == null || !saved.exists() || saved.length() < 1024) {
                if (saved != null) saved.delete();
                edit.putString("last_error", "ضبط خیلی کوتاه بود یا ذخیره نشد.").apply();
                return false;
            }
            boolean silent = peak < SILENCE_PEAK;
            try {
                JSONObject meta = new JSONObject();
                meta.put("startedAt", startedAt);
                meta.put("endedAt", endedAt);
                meta.put("durationMs", endedAt - startedAt);
                meta.put("number", number);
                meta.put("direction", direction);
                meta.put("source", manual ? "manual" : "a11y");
                meta.put("audioSource", sourceName);
                meta.put("peak", peak);
                meta.put("silent", silent);
                String name = saved.getName();
                int dot = name.lastIndexOf('.');
                File sidecar = new File(saved.getParentFile(), name.substring(0, dot) + ".json");
                try (FileOutputStream out = new FileOutputStream(sidecar)) {
                    out.write(meta.toString().getBytes(StandardCharsets.UTF_8));
                }
            } catch (Throwable ignored) {
            }
            edit.putLong("last_recording_at", endedAt);
            edit.putString("last_error", silent
                    ? "آخرین ضبط بی‌صدا بود: این گوشی در زمان تماس میکروفون را در اختیار برنامه نمی‌گذارد "
                    + "(بلندگو را روشن کنید یا از ضبط‌کننده‌ی خودِ گوشی استفاده کنید)."
                    : "");
            edit.apply();
            return true;
        }
    }

    static String lastError(Context c) {
        return prefs(c).getString("last_error", "");
    }
}
