package com.amirali.smsbridge;

import android.accessibilityservice.AccessibilityService;
import android.content.ComponentName;
import android.content.Context;
import android.provider.Settings;
import android.view.accessibility.AccessibilityEvent;

/**
 * سرویس دسترس‌پذیری که فقط یک کار دارد: روشن بودنش به برنامه اجازه می‌دهد وقتی در پس‌زمینه
 * است هم از میکروفون ضبط کند (اندروید ۹ به بعد ضبط پس‌زمینه را برای برنامه‌های عادی
 * ساکت می‌کند، ولی برنامه‌ای که سرویس دسترس‌پذیری فعال دارد مستثنا است).
 *
 * این سرویس هیچ محتوای صفحه‌ای را نمی‌خواند و رویداد پردازش نمی‌کند؛ شروع و پایان ضبط را
 * {@link PhoneStateReceiver} هنگام تغییر وضعیت تماس تعیین می‌کند. برنامه از فروشگاه
 * Google Play نصب نمی‌شود، پس سیاست آن فروشگاه درباره‌ی دسترس‌پذیری اینجا مطرح نیست.
 */
public class CallRecorderAccessibilityService extends AccessibilityService {
    private static volatile boolean connected = false;

    static boolean isConnected() {
        return connected;
    }

    /** روشن بودن سرویس در تنظیمات سیستم (حتی اگر فرایند هنوز اتصال نگرفته). */
    static boolean isEnabledInSettings(Context context) {
        try {
            String enabled = Settings.Secure.getString(
                    context.getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
            if (enabled == null || enabled.isEmpty()) return false;
            ComponentName self = new ComponentName(context, CallRecorderAccessibilityService.class);
            String flat = self.flattenToString();
            String shortFlat = self.flattenToShortString();
            for (String item : enabled.split(":")) {
                if (item.equalsIgnoreCase(flat) || item.equalsIgnoreCase(shortFlat)) return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        connected = true;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // عمداً خالی: این سرویس فقط برای باقی‌ماندن فرایند و اجازه‌ی ضبط پس‌زمینه است.
    }

    @Override
    public void onInterrupt() {
    }

    @Override
    public boolean onUnbind(android.content.Intent intent) {
        connected = false;
        return super.onUnbind(intent);
    }

    @Override
    public void onDestroy() {
        connected = false;
        super.onDestroy();
    }
}
