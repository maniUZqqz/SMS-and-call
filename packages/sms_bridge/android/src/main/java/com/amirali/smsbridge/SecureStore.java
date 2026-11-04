package com.amirali.smsbridge;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * ذخیره‌ی امنِ مقادیر حساس (کلید API، توکن). مقدار با AES-256-GCM و کلیدی رمز می‌شود که
 * در Android Keystore ساخته شده و از دستگاه خارج نمی‌شود؛ فقط متن رمزشده در SharedPreferences می‌ماند.
 */
final class SecureStore {
    private static final String ALIAS = "sms_and_call_secure_v1";
    private static final String PREFS = "smsbridge_secure";

    private SecureStore() {
    }

    private static SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        if (!store.containsAlias(ALIAS)) {
            KeyGenerator generator = KeyGenerator.getInstance(
                    KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(
                    ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build());
            generator.generateKey();
        }
        return (SecretKey) store.getKey(ALIAS, null);
    }

    static boolean write(Context context, String name, String value) {
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key());
            byte[] iv = cipher.getIV();
            byte[] encrypted = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
            String stored = Base64.encodeToString(iv, Base64.NO_WRAP) + ":"
                    + Base64.encodeToString(encrypted, Base64.NO_WRAP);
            prefs(context).edit().putString(name, stored).apply();
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    static String read(Context context, String name) {
        try {
            String stored = prefs(context).getString(name, null);
            if (stored == null) return "";
            int split = stored.indexOf(':');
            if (split <= 0) return "";
            byte[] iv = Base64.decode(stored.substring(0, split), Base64.NO_WRAP);
            byte[] encrypted = Base64.decode(stored.substring(split + 1), Base64.NO_WRAP);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, iv));
            return new String(cipher.doFinal(encrypted), StandardCharsets.UTF_8);
        } catch (Throwable t) {
            return "";
        }
    }

    static boolean delete(Context context, String name) {
        prefs(context).edit().remove(name).apply();
        return true;
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
