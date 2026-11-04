package com.amirali.smsbridge;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;

import androidx.core.content.FileProvider;

import java.io.File;

/** اشتراک‌گذاری متن و فایل (ضبط صوتی، فایل متنی رونوشت) از طریق منوی اشتراک اندروید. */
final class ShareHelper {
    private ShareHelper() {
    }

    static boolean shareText(Context context, String text, String subject) {
        try {
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType("text/plain");
            send.putExtra(Intent.EXTRA_TEXT, text);
            if (subject != null && !subject.isEmpty()) send.putExtra(Intent.EXTRA_SUBJECT, subject);
            Intent chooser = Intent.createChooser(send, null);
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(chooser);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    static boolean shareFile(Context context, String path, String mime, String subject) {
        try {
            File file = new File(path);
            if (!file.exists()) return false;
            Uri uri = FileProvider.getUriForFile(
                    context, context.getPackageName() + ".smsbridge.fileprovider", file);
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType(mime == null || mime.isEmpty() ? "*/*" : mime);
            send.putExtra(Intent.EXTRA_STREAM, uri);
            if (subject != null && !subject.isEmpty()) send.putExtra(Intent.EXTRA_SUBJECT, subject);
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            Intent chooser = Intent.createChooser(send, null);
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);
            context.startActivity(chooser);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }
}
