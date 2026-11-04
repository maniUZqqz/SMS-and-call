package com.amirali.smsbridge;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.CallLog;
import android.provider.MediaStore;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * خواندن تاریخچه‌ی تماس و فایل‌های صوتی (MediaStore) و کپی یک فایل به حافظه‌ی داخلی برنامه.
 * همه‌ی متدها هنگام نبودن مجوز، لیست خالی یا null برمی‌گردانند و استثنا نمی‌اندازند.
 */
final class CallMedia {
    private CallMedia() {
    }

    static List<Map<String, Object>> queryCallLog(Context context, long sinceMillis, int limit) {
        List<Map<String, Object>> out = new ArrayList<>();
        try {
            String[] projection = new String[]{
                    CallLog.Calls._ID,
                    CallLog.Calls.NUMBER,
                    CallLog.Calls.CACHED_NAME,
                    CallLog.Calls.DATE,
                    CallLog.Calls.DURATION,
                    CallLog.Calls.TYPE
            };
            int safeLimit = Math.max(1, Math.min(limit, 5000));
            String selection = CallLog.Calls.DATE + " >= ?";
            String[] selectionArgs = new String[]{String.valueOf(Math.max(0L, sinceMillis))};
            Cursor cursor;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // از اندروید ۱۱ ارائه‌دهنده‌ی تاریخچه‌ی تماس «LIMIT» داخل sortOrder را رد می‌کند
                Bundle args = new Bundle();
                args.putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection);
                args.putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs);
                args.putStringArray(ContentResolver.QUERY_ARG_SORT_COLUMNS, new String[]{CallLog.Calls.DATE});
                args.putInt(ContentResolver.QUERY_ARG_SORT_DIRECTION,
                        ContentResolver.QUERY_SORT_DIRECTION_DESCENDING);
                args.putInt(ContentResolver.QUERY_ARG_LIMIT, safeLimit);
                cursor = context.getContentResolver().query(CallLog.Calls.CONTENT_URI, projection, args, null);
            } else {
                cursor = context.getContentResolver().query(
                        CallLog.Calls.CONTENT_URI, projection, selection, selectionArgs,
                        CallLog.Calls.DATE + " DESC LIMIT " + safeLimit);
            }
            try {
                if (cursor == null) return out;
                while (cursor.moveToNext()) {
                    Map<String, Object> row = new HashMap<>();
                    row.put("id", cursor.getLong(0));
                    row.put("number", cursor.getString(1) == null ? "" : cursor.getString(1));
                    row.put("name", cursor.getString(2) == null ? "" : cursor.getString(2));
                    row.put("date", cursor.getLong(3));
                    row.put("duration", cursor.getLong(4));
                    row.put("type", cursor.getInt(5));
                    out.add(row);
                }
            } finally {
                if (cursor != null) cursor.close();
            }
        } catch (SecurityException e) {
            // مجوز READ_CALL_LOG داده نشده
        } catch (Throwable ignored) {
        }
        return out;
    }

    static List<Map<String, Object>> queryAudioFiles(Context context, long sinceMillis, int limit) {
        List<Map<String, Object>> out = new ArrayList<>();
        try {
            Uri collection = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                    ? MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                    : MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;

            List<String> columns = new ArrayList<>();
            columns.add(MediaStore.Audio.Media._ID);
            columns.add(MediaStore.Audio.Media.DISPLAY_NAME);
            columns.add(MediaStore.Audio.Media.MIME_TYPE);
            columns.add(MediaStore.Audio.Media.SIZE);
            columns.add(MediaStore.Audio.Media.DURATION);
            columns.add(MediaStore.Audio.Media.DATE_ADDED);
            columns.add(MediaStore.Audio.Media.DATE_MODIFIED);
            final boolean hasRelative = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q;
            if (hasRelative) {
                columns.add(MediaStore.Audio.Media.RELATIVE_PATH);
            } else {
                columns.add(MediaStore.Audio.Media.DATA);
            }

            long sinceSeconds = Math.max(0L, sinceMillis / 1000L);
            String selection = "(" + MediaStore.Audio.Media.DATE_ADDED + " >= ? OR "
                    + MediaStore.Audio.Media.DATE_MODIFIED + " >= ?)";
            String[] args = new String[]{String.valueOf(sinceSeconds), String.valueOf(sinceSeconds)};

            int safeLimit = Math.max(1, Math.min(limit, 5000));
            String root = Environment.getExternalStorageDirectory().getAbsolutePath();

            ContentResolver resolver = context.getContentResolver();
            try (Cursor cursor = resolver.query(
                    collection,
                    columns.toArray(new String[0]),
                    selection,
                    args,
                    MediaStore.Audio.Media.DATE_ADDED + " ASC")) {
                if (cursor == null) return out;
                int count = 0;
                while (cursor.moveToNext() && count < safeLimit) {
                    long id = cursor.getLong(0);
                    String name = cursor.getString(1) == null ? "" : cursor.getString(1);
                    String mime = cursor.getString(2) == null ? "" : cursor.getString(2);
                    long size = cursor.getLong(3);
                    long duration = cursor.getLong(4);
                    long added = cursor.getLong(5);
                    long modified = cursor.getLong(6);
                    String path = cursor.getString(7) == null ? "" : cursor.getString(7);
                    String relative = path;
                    if (!hasRelative) {
                        // DATA مسیر کامل فایل است؛ نسبت به ریشه‌ی حافظه و بدون نام فایل
                        relative = path;
                        if (relative.startsWith(root)) relative = relative.substring(root.length());
                        int slash = relative.lastIndexOf('/');
                        relative = slash >= 0 ? relative.substring(0, slash + 1) : "";
                        while (relative.startsWith("/")) relative = relative.substring(1);
                    }

                    Map<String, Object> row = new HashMap<>();
                    row.put("id", id);
                    row.put("uri", ContentUris.withAppendedId(collection, id).toString());
                    row.put("displayName", name);
                    row.put("relativePath", relative);
                    row.put("mime", mime);
                    row.put("size", size);
                    row.put("durationMs", duration);
                    row.put("dateAdded", added * 1000L);
                    row.put("dateModified", modified * 1000L);
                    out.add(row);
                    count++;
                }
            }
        } catch (SecurityException e) {
            // مجوز خواندن فایل‌های صوتی داده نشده
        } catch (Throwable ignored) {
        }
        return out;
    }

    /** محتوای یک آدرس را به مسیر مقصد کپی می‌کند. مسیر مقصد یا null. */
    static String copyUriToFile(Context context, String uriString, String destination) {
        File out = new File(destination);
        File parent = out.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();
        File tmp = new File(destination + ".part");
        try (InputStream in = context.getContentResolver().openInputStream(Uri.parse(uriString));
             FileOutputStream sink = new FileOutputStream(tmp)) {
            if (in == null) return null;
            byte[] buffer = new byte[64 * 1024];
            int n;
            while ((n = in.read(buffer)) >= 0) {
                if (n > 0) sink.write(buffer, 0, n);
            }
            sink.flush();
        } catch (Throwable t) {
            tmp.delete();
            return null;
        }
        if (out.exists() && !out.delete()) {
            tmp.delete();
            return null;
        }
        if (!tmp.renameTo(out)) {
            tmp.delete();
            return null;
        }
        return out.getAbsolutePath();
    }
}
