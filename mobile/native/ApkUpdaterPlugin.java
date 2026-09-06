package com.tuleh.kasir;

// Auto-Update Tahap 4 — plugin Capacitor untuk unduh + pasang APK di dalam app.
//  - Unduh: DownloadManager (resume, progres, notifikasi bawaan sistem).
//  - Pasang: FileProvider + Intent ACTION_VIEW (memakai izin REQUEST_INSTALL_PACKAGES).
//    Bila unduhan selesai saat app di latar belakang (Android 10+ melarang membuka
//    Activity dari latar), pemasang dibuka OTOMATIS saat app kembali ke depan dan
//    ada notifikasi "siap dipasang" yang langsung membuka pemasang saat diketuk.
//  - Izin "Instal aplikasi tak dikenal": dicek (canInstall) & dibuka (openInstallPermission).
// Disuntik ke modul app oleh CI setelah `cap add android`; didaftarkan di MainActivity.

import android.app.DownloadManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import androidx.core.content.FileProvider;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;

@CapacitorPlugin(name = "ApkUpdater")
public class ApkUpdaterPlugin extends Plugin {

    private long downloadId = -1L;
    private BroadcastReceiver receiver;
    private Runnable poller;
    private final Handler handler = new Handler(Looper.getMainLooper());

    // Pemasangan tertunda (unduhan selesai saat app di latar belakang).
    private File pendingInstall;
    private boolean diDepan = false;
    private static final String KANAL_PEMBARUAN = "tuleh_pembaruan";
    private static final int ID_NOTIF_PEMBARUAN = 7301;

    /** Apakah pengguna sudah mengizinkan pemasangan dari sumber tak dikenal. */
    @PluginMethod
    public void canInstall(PluginCall call) {
        boolean granted = true;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            granted = getContext().getPackageManager().canRequestPackageInstalls();
        }
        JSObject ret = new JSObject();
        ret.put("granted", granted);
        call.resolve(ret);
    }

    /** Buka layar sistem "Instal aplikasi tak dikenal" untuk paket ini. */
    @PluginMethod
    public void openInstallPermission(PluginCall call) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + getContext().getPackageName()));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try { getContext().startActivity(intent); } catch (Exception ignored) {}
        }
        call.resolve();
    }

    /** Unduh APK via DownloadManager. Emit event "progress" {percent}; resolve {path}. */
    @PluginMethod
    public void download(PluginCall call) {
        final String url = call.getString("url");
        if (url == null || !url.startsWith("https://")) {
            call.reject("URL unduhan tidak valid.");
            return;
        }
        final String filename = call.getString("filename", "tuleh-update.apk");

        File dir = getContext().getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
        if (dir == null) { call.reject("Penyimpanan tidak tersedia."); return; }
        final File dest = new File(dir, filename);
        if (dest.exists()) { try { dest.delete(); } catch (Exception ignored) {} }

        final DownloadManager dm = (DownloadManager) getContext().getSystemService(Context.DOWNLOAD_SERVICE);
        DownloadManager.Request req = new DownloadManager.Request(Uri.parse(url));
        req.setTitle("Tuléh — Pembaruan");
        req.setDescription("Mengunduh versi terbaru…");
        req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE);
        req.setDestinationInExternalFilesDir(getContext(), Environment.DIRECTORY_DOWNLOADS, filename);
        req.setMimeType("application/vnd.android.package-archive");
        downloadId = dm.enqueue(req);

        receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                long id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L);
                if (id != downloadId) return;
                stopPolling();
                unregister();
                int status = queryStatus(dm);
                if (status == DownloadManager.STATUS_SUCCESSFUL) {
                    notifyProgress(100);
                    JSObject ret = new JSObject();
                    ret.put("path", dest.getAbsolutePath());
                    call.resolve(ret);
                } else {
                    call.reject("Unduhan gagal (status " + status + ").");
                }
            }
        };
        IntentFilter filter = new IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE);
        if (Build.VERSION.SDK_INT >= 33) {
            getContext().registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
        } else {
            getContext().registerReceiver(receiver, filter);
        }
        startPolling(dm);
    }

    /** Pasang APK yang sudah diunduh (membuka pemasang sistem). */
    @PluginMethod
    public void install(PluginCall call) {
        String path = call.getString("path");
        if (path == null) { call.reject("Path berkas kosong."); return; }
        try {
            boolean launched = pasangAtauTunda(new File(path));
            JSObject ret = new JSObject();
            ret.put("launched", launched);
            call.resolve(ret);
        } catch (Exception e) {
            call.reject("Gagal membuka pemasang: " + e.getMessage());
        }
    }

    private Intent intentPasang(File file) {
        Uri uri = FileProvider.getUriForFile(getContext(),
                getContext().getPackageName() + ".fileprovider", file);
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri, "application/vnd.android.package-archive");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        return intent;
    }

    private void installApk(File file) {
        getContext().startActivity(intentPasang(file));
    }

    /** Buka pemasang bila app di depan; bila di latar belakang, tunda (dibuka
     *  otomatis di handleOnResume) + notifikasi yang membuka pemasang saat diketuk. */
    private boolean pasangAtauTunda(File file) {
        if (diDepan) {
            pendingInstall = null;
            hapusNotifPembaruan();
            installApk(file);
            return true;
        }
        pendingInstall = file;
        tampilkanNotifSiapDipasang(file);
        return false;
    }

    private void tampilkanNotifSiapDipasang(File file) {
        try {
            NotificationManager nm = (NotificationManager) getContext().getSystemService(Context.NOTIFICATION_SERVICE);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                NotificationChannel ch = new NotificationChannel(KANAL_PEMBARUAN, "Pembaruan aplikasi",
                        NotificationManager.IMPORTANCE_HIGH);
                ch.setDescription("Pemberitahuan saat pembaruan Tuléh siap dipasang.");
                nm.createNotificationChannel(ch);
            }
            int flags = PendingIntent.FLAG_UPDATE_CURRENT
                    | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
            PendingIntent pi = PendingIntent.getActivity(getContext(), ID_NOTIF_PEMBARUAN, intentPasang(file), flags);
            Notification.Builder b = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ? new Notification.Builder(getContext(), KANAL_PEMBARUAN)
                    : new Notification.Builder(getContext());
            Notification n = b.setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setContentTitle("Pembaruan Tuléh siap dipasang")
                    .setContentText("Ketuk untuk memasang versi terbaru.")
                    .setContentIntent(pi)
                    .setAutoCancel(true)
                    .build();
            nm.notify(ID_NOTIF_PEMBARUAN, n);
        } catch (Exception ignored) {
            // Notifikasi hanya pelengkap; handleOnResume tetap membuka pemasang.
        }
    }

    private void hapusNotifPembaruan() {
        try {
            ((NotificationManager) getContext().getSystemService(Context.NOTIFICATION_SERVICE)).cancel(ID_NOTIF_PEMBARUAN);
        } catch (Exception ignored) {}
    }

    @Override
    protected void handleOnResume() {
        super.handleOnResume();
        diDepan = true;
        final File tertunda = pendingInstall;
        if (tertunda == null) return;
        pendingInstall = null;
        hapusNotifPembaruan();
        handler.postDelayed(new Runnable() {
            @Override
            public void run() { try { installApk(tertunda); } catch (Exception ignored) {} }
        }, 250);
    }

    @Override
    protected void handleOnPause() {
        diDepan = false;
        super.handleOnPause();
    }

    // ---- Progres via polling kursor DownloadManager ----
    private void startPolling(final DownloadManager dm) {
        poller = new Runnable() {
            @Override
            public void run() {
                DownloadManager.Query q = new DownloadManager.Query().setFilterById(downloadId);
                Cursor cur = null;
                try {
                    cur = dm.query(q);
                    if (cur != null && cur.moveToFirst()) {
                        long dl = cur.getLong(cur.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
                        long total = cur.getLong(cur.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES));
                        if (total > 0) notifyProgress((int) (dl * 100L / total));
                    }
                } catch (Exception ignored) {
                } finally {
                    if (cur != null) cur.close();
                }
                handler.postDelayed(poller, 500);
            }
        };
        handler.postDelayed(poller, 500);
    }

    private void stopPolling() {
        if (poller != null) handler.removeCallbacks(poller);
        poller = null;
    }

    private void unregister() {
        if (receiver != null) {
            try { getContext().unregisterReceiver(receiver); } catch (Exception ignored) {}
            receiver = null;
        }
    }

    private int queryStatus(DownloadManager dm) {
        DownloadManager.Query q = new DownloadManager.Query().setFilterById(downloadId);
        Cursor cur = null;
        int status = -1;
        try {
            cur = dm.query(q);
            if (cur != null && cur.moveToFirst()) {
                status = cur.getInt(cur.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
            }
        } catch (Exception ignored) {
        } finally {
            if (cur != null) cur.close();
        }
        return status;
    }

    private void notifyProgress(int percent) {
        JSObject data = new JSObject();
        data.put("percent", Math.max(0, Math.min(100, percent)));
        notifyListeners("progress", data);
    }
}
