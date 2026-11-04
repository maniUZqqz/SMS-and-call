package com.amirali.smsbridge;

import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

/**
 * باز کردن صفحه‌های تنظیمات که برای پایداری لازم‌اند. صفحه‌ی «شروع خودکار/Autostart»
 * سازنده‌ها استاندارد نیست؛ اینجا چند نام شناخته‌شده امتحان می‌شود (بهترین تلاش) و در
 * صورت نبودن، صفحه‌ی اطلاعات برنامه باز می‌شود.
 */
final class OemSettings {
    private OemSettings() {
    }

    private static final String[][] AUTOSTART_COMPONENTS = new String[][]{
            // Xiaomi / Redmi / POCO (MIUI، HyperOS)
            {"com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"},
            // Huawei / Honor
            {"com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"},
            {"com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"},
            {"com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"},
            // Oppo / Realme (ColorOS)
            {"com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"},
            {"com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"},
            {"com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"},
            // Vivo / iQOO
            {"com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"},
            {"com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"},
            // OnePlus
            {"com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"},
            // Samsung (مدیریت باتری)
            {"com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"},
            {"com.samsung.android.sm_cn", "com.samsung.android.sm.ui.battery.BatteryActivity"},
            // Asus
            {"com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity"},
    };

    static boolean openAutoStart(Context context) {
        for (String[] pair : AUTOSTART_COMPONENTS) {
            try {
                Intent intent = new Intent();
                intent.setComponent(new ComponentName(pair[0], pair[1]));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(intent);
                return true;
            } catch (ActivityNotFoundException ignored) {
            } catch (SecurityException ignored) {
            } catch (Throwable ignored) {
            }
        }
        return openAppDetails(context);
    }

    static boolean openAppDetails(Context context) {
        try {
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
            intent.setData(Uri.parse("package:" + context.getPackageName()));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
            return false; // صفحه‌ی اختصاصی سازنده پیدا نشد
        } catch (Throwable t) {
            return false;
        }
    }

    static boolean openExactAlarm(Context context) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Intent intent = new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM);
                intent.setData(Uri.parse("package:" + context.getPackageName()));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(intent);
                return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    static boolean openAccessibility(Context context) {
        try {
            Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }
}
