package com.amirali.smsbridge;

import android.media.MediaPlayer;

import java.util.HashMap;
import java.util.Map;

/** پخش‌کننده‌ی ساده‌ی صوتی برای گوش دادن به ضبط‌ها داخل برنامه. */
final class AudioPlayerBridge {
    private MediaPlayer player;
    private String path = "";
    private boolean prepared = false;

    synchronized boolean play(String filePath) {
        stop();
        try {
            MediaPlayer p = new MediaPlayer();
            p.setDataSource(filePath);
            p.setOnCompletionListener(new MediaPlayer.OnCompletionListener() {
                @Override
                public void onCompletion(MediaPlayer mp) {
                    // پخش تمام شد؛ وضعیت با playerState خوانده می‌شود
                }
            });
            p.prepare();
            p.start();
            player = p;
            path = filePath;
            prepared = true;
            return true;
        } catch (Throwable t) {
            stop();
            return false;
        }
    }

    synchronized boolean pause() {
        try {
            if (player != null && player.isPlaying()) player.pause();
            return player != null;
        } catch (Throwable t) {
            return false;
        }
    }

    synchronized boolean resume() {
        try {
            if (player == null) return false;
            player.start();
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    synchronized boolean seek(int positionMs) {
        try {
            if (player == null) return false;
            player.seekTo(Math.max(0, positionMs));
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    synchronized boolean stop() {
        try {
            if (player != null) {
                try {
                    player.stop();
                } catch (Throwable ignored) {
                }
                player.release();
            }
        } catch (Throwable ignored) {
        }
        player = null;
        path = "";
        prepared = false;
        return true;
    }

    synchronized Map<String, Object> state() {
        Map<String, Object> m = new HashMap<>();
        boolean playing = false;
        int position = 0;
        int duration = 0;
        try {
            if (player != null && prepared) {
                playing = player.isPlaying();
                position = player.getCurrentPosition();
                duration = player.getDuration();
            }
        } catch (Throwable ignored) {
        }
        m.put("playing", playing);
        m.put("positionMs", position);
        m.put("durationMs", duration);
        m.put("path", path);
        return m;
    }
}
