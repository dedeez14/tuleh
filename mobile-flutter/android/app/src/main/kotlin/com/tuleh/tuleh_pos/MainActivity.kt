package com.tuleh.tuleh_pos

import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import java.security.MessageDigest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Auto-Update in-app (Android). Port native dari ApkUpdaterPlugin Capacitor:
///  - Unduh: DownloadManager (progres via polling + watchdog stall + notifikasi).
///  - Pasang: FileProvider + Intent ACTION_VIEW (izin REQUEST_INSTALL_PACKAGES),
///    hanya bila nama paket APK == paket app ini (cegah pasang APK asing).
///    Bila unduhan selesai saat app di latar belakang (Android 10+ melarang
///    membuka Activity dari latar), pemasang dibuka OTOMATIS saat app kembali
///    ke depan + notifikasi "siap dipasang" yang bisa diketuk.
///  - Izin "Instal aplikasi tak dikenal": canInstall / openInstallPermission.
/// Diekspos ke Dart lewat MethodChannel "tuleh/updater" + EventChannel progres.
class MainActivity : FlutterActivity() {

    private val methodChannelName = "tuleh/updater"
    private val eventChannelName = "tuleh/updater/progress"

    // Sumber APK yang diizinkan — HARUS sama dengan lib/features/update/domain/
    // sumber_apk.dart (Dart memilih aset & tombol; ini penegakan akhir):
    //  - tatreport.com dan subdomainnya (server MOVERA, /app/versi), path bebas;
    //  - github.com hanya path aset Release repo ini (APK Flutter diterbitkan
    //    di sana; DownloadManager mengikuti redirect ke objects.githubusercontent.com
    //    sendiri, cek ini hanya pada URL awal).
    private val allowedHostSuffix = "tatreport.com"
    private val githubReleasePathPrefix = "/dedeez14/tuleh/releases/download/"

    // Ambang macet: tanpa penambahan byte selama ~30 dtk (60 × 500ms) → gagalkan.
    private val stallTicksLimit = 60

    private var downloadId = -1L
    private var receiver: BroadcastReceiver? = null
    private var poller: Runnable? = null
    private val handler = Handler(Looper.getMainLooper())
    private var progressSink: EventChannel.EventSink? = null

    // Result unduhan yang tertunda (di-resolve oleh receiver, watchdog, atau cancel).
    private var pendingResult: MethodChannel.Result? = null
    private var resolved = false
    private var lastBytes = -1L
    private var stallTicks = 0

    // Pemasangan tertunda: APK yang siap tetapi app sedang di latar belakang.
    private var pendingInstall: File? = null
    private var diDepan = false
    private val kanalPembaruan = "tuleh_pembaruan"
    private val idNotifPembaruan = 7301

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, eventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }
                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            }
        )

        // Identitas perangkat untuk masa coba Mode Demo (lapis 2): ANDROID_ID
        // bertahan saat aplikasi dihapus/dipasang ulang (kunci tanda tangan sama),
        // berubah hanya saat factory reset. Hash dilakukan di Dart.
        MethodChannel(messenger, "tuleh/perangkat").setMethodCallHandler { call, result ->
            when (call.method) {
                "androidId" -> {
                    val id = try {
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    } catch (_: Exception) { null }
                    result.success(id ?: "")
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        packageManager.canRequestPackageInstalls() else true
                    result.success(granted)
                }
                "openInstallPermission" -> {
                    var ok = true
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        try { startActivity(intent) } catch (_: Exception) { ok = false }
                    }
                    result.success(ok)
                }
                // Folder unduhan app (dibagikan ke pemasang lewat FileProvider
                // external-files-path). Unduhan utama kini dilakukan Dart (Dio);
                // DownloadManager di bawah tinggal cadangan.
                "downloadDir" -> {
                    val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                    if (dir == null) result.error("STORAGE", "Penyimpanan tidak tersedia.", null)
                    else result.success(dir.absolutePath)
                }
                // Info paket terpasang: versi + sidik jari tanda tangan (diagnosa).
                "infoPaket" -> {
                    try {
                        val info = packageInfoTerpasang()
                        result.success(mapOf(
                            "versionName" to (info.versionName ?: ""),
                            "versionCode" to kodeVersi(info),
                            "signatureSha256" to (sidikJari(info) ?: "")
                        ))
                    } catch (e: Exception) {
                        result.error("INFO", e.message, null)
                    }
                }
                "download" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename") ?: "tuleh-update.apk"
                    if (url == null || !url.startsWith("https://") || !hostAllowed(url)) {
                        result.error("URL", "URL unduhan tidak valid / host tidak diizinkan.", null)
                    } else {
                        startDownload(url, filename, result)
                    }
                }
                "cancel" -> {
                    cancelDownload("Unduhan dibatalkan.")
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("PATH", "Path berkas kosong.", null)
                    } else {
                        val file = File(path)
                        val masalah = periksaBerkasPembaruan(file)
                        if (masalah != null) {
                            result.error(masalah.first, masalah.second, null)
                        } else {
                            try {
                                val launched = pasangAtauTunda(file)
                                result.success(mapOf("launched" to launched))
                            } catch (e: Exception) {
                                result.error("INSTALL", "Gagal membuka pemasang: ${e.message}", null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hostAllowed(url: String): Boolean {
        val uri = Uri.parse(url)
        val host = uri.host?.lowercase() ?: return false
        if (host == allowedHostSuffix || host.endsWith(".$allowedHostSuffix")) return true
        if (host == "github.com" || host == "www.github.com") {
            return (uri.path ?: "").startsWith(githubReleasePathPrefix)
        }
        return false
    }

    /// Periksa APK SEBELUM pemasang sistem dibuka, supaya kegagalan punya
    /// sebab yang jelas (pemasang sistem hanya bilang "Aplikasi tidak
    /// terpasang"). Mengembalikan (kode, pesan) atau null bila sah.
    private fun periksaBerkasPembaruan(file: File): Pair<String, String>? {
        if (!file.exists() || file.length() < 1024L * 100) {
            return "BERKAS" to "Berkas pembaruan tidak lengkap (${file.length()} byte). Unduh ulang."
        }
        val arsip = try {
            packageManager.getPackageArchiveInfo(file.absolutePath, flagTandaTangan())
        } catch (e: Exception) { null }
            ?: return "BERKAS" to "Berkas pembaruan tidak bisa dibaca sebagai APK. Unduh ulang."
        if (arsip.packageName != packageName) {
            return "MISMATCH" to "Berkas pembaruan untuk paket lain (${arsip.packageName}), bukan aplikasi ini."
        }
        val terpasang = try { packageInfoTerpasang() } catch (_: Exception) { null }
        if (terpasang != null) {
            val kodeBaru = kodeVersi(arsip)
            val kodeLama = kodeVersi(terpasang)
            if (kodeBaru in 1..kodeLama) {
                return "VERSI" to "Berkas ${arsip.versionName} (kode $kodeBaru) bukan versi lebih baru dari yang terpasang " +
                    "(${terpasang.versionName}, kode $kodeLama)."
            }
            val sidikBaru = sidikJari(arsip)
            val sidikLama = sidikJari(terpasang)
            if (sidikBaru != null && sidikLama != null && sidikBaru != sidikLama) {
                return "TANDA_TANGAN" to "Aplikasi yang terpasang ditandatangani kunci berbeda dari rilis resmi " +
                    "(biasanya dipasang dari build lokal/debug), jadi Android menolak menimpanya. " +
                    "Hapus aplikasi ini lalu pasang APK terbaru dari GitHub sekali; pembaruan berikutnya otomatis."
            }
        }
        return null
    }

    private fun flagTandaTangan(): Int =
        if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
        else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES

    private fun packageInfoTerpasang(): PackageInfo =
        packageManager.getPackageInfo(packageName, flagTandaTangan())

    private fun kodeVersi(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()

    /// SHA-256 sertifikat penandatangan pertama (hex kecil), atau null.
    private fun sidikJari(info: PackageInfo): String? {
        val sig = if (Build.VERSION.SDK_INT >= 28) {
            val si = info.signingInfo ?: return null
            (if (si.hasMultipleSigners()) si.apkContentsSigners else si.signingCertificateHistory)?.firstOrNull()
        } else {
            @Suppress("DEPRECATION") info.signatures?.firstOrNull()
        } ?: return null
        val d = MessageDigest.getInstance("SHA-256").digest(sig.toByteArray())
        return d.joinToString("") { "%02x".format(it) }
    }

    /// Unduh APK via DownloadManager → resolve path lokal. Emit progres 0..100.
    private fun startDownload(url: String, filename: String, result: MethodChannel.Result) {
        // Bereskan unduhan sebelumnya bila masih ada (re-entrancy aman).
        cancelDownload(null)

        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        if (dir == null) {
            result.error("STORAGE", "Penyimpanan tidak tersedia.", null); return
        }
        val dest = File(dir, filename)
        if (dest.exists()) { try { dest.delete() } catch (_: Exception) {} }

        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val req = DownloadManager.Request(Uri.parse(url))
            .setTitle("Tuléh — Pembaruan")
            .setDescription("Mengunduh versi terbaru…")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, filename)
            .setMimeType("application/vnd.android.package-archive")
        downloadId = dm.enqueue(req)
        pendingResult = result
        resolved = false
        lastBytes = -1L
        stallTicks = 0

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val id = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) ?: -1L
                if (id != downloadId) return
                stopPolling(); unregister()
                val status = queryStatus(dm)
                if (status == DownloadManager.STATUS_SUCCESSFUL) {
                    notifyProgress(100)
                    resolveSuccess(dest.absolutePath)
                } else {
                    resolveError("DOWNLOAD", "Unduhan gagal (status $status).")
                }
            }
        }
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        startPolling(dm)
    }

    private fun intentPasang(file: File): Intent {
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        return Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun installApk(file: File) {
        startActivity(intentPasang(file))
    }

    /// Buka pemasang bila app di depan; bila di latar belakang, simpan sebagai
    /// tertunda (dibuka otomatis di onResume) dan tampilkan notifikasi yang
    /// langsung membuka pemasang saat diketuk. Mengembalikan true bila pemasang
    /// langsung dibuka.
    private fun pasangAtauTunda(file: File): Boolean {
        if (diDepan) {
            pendingInstall = null
            hapusNotifPembaruan()
            installApk(file)
            return true
        }
        pendingInstall = file
        tampilkanNotifSiapDipasang(file)
        return false
    }

    private fun tampilkanNotifSiapDipasang(file: File) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(
                    NotificationChannel(kanalPembaruan, "Pembaruan aplikasi",
                        NotificationManager.IMPORTANCE_HIGH).apply {
                        description = "Pemberitahuan saat pembaruan Tuléh siap dipasang."
                    }
                )
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
            val pi = PendingIntent.getActivity(this, idNotifPembaruan, intentPasang(file), flags)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(this, kanalPembaruan) else @Suppress("DEPRECATION") Notification.Builder(this)
            val notif = builder
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("Pembaruan Tuléh siap dipasang")
                .setContentText("Ketuk untuk memasang versi terbaru.")
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build()
            nm.notify(idNotifPembaruan, notif)
        } catch (_: Exception) {
            // Notifikasi hanya pelengkap; onResume tetap membuka pemasang.
        }
    }

    private fun hapusNotifPembaruan() {
        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(idNotifPembaruan)
        } catch (_: Exception) {}
    }

    override fun onResume() {
        super.onResume()
        diDepan = true
        val tertunda = pendingInstall ?: return
        pendingInstall = null
        hapusNotifPembaruan()
        // Beri jeda singkat agar Activity benar-benar di depan sebelum membuka pemasang.
        handler.postDelayed({ try { installApk(tertunda) } catch (_: Exception) {} }, 250)
    }

    override fun onPause() {
        diDepan = false
        super.onPause()
    }

    /// Batalkan unduhan berjalan (dan resolve error bila diminta pengguna).
    private fun cancelDownload(userMessage: String?) {
        stopPolling()
        unregister()
        if (downloadId != -1L) {
            try {
                val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                dm.remove(downloadId)
            } catch (_: Exception) {}
        }
        downloadId = -1L
        if (userMessage != null) resolveError("CANCEL", userMessage)
        else { pendingResult = null; resolved = true }
    }

    // ---- Progres + watchdog macet via polling kursor DownloadManager ----
    private fun startPolling(dm: DownloadManager) {
        val r = object : Runnable {
            override fun run() {
                val q = DownloadManager.Query().setFilterById(downloadId)
                var cur: Cursor? = null
                try {
                    cur = dm.query(q)
                    if (cur != null && cur.moveToFirst()) {
                        val dl = cur.getLong(cur.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                        val total = cur.getLong(cur.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                        if (total > 0) notifyProgress((dl * 100L / total).toInt())
                        // Watchdog: byte tak bertambah terlalu lama → gagalkan (mis. jaringan putus).
                        if (dl == lastBytes) stallTicks++ else { stallTicks = 0; lastBytes = dl }
                        if (stallTicks >= stallTicksLimit) {
                            cancelDownload("Unduhan macet — periksa koneksi lalu coba lagi.")
                            return
                        }
                    }
                } catch (_: Exception) {
                } finally {
                    cur?.close()
                }
                handler.postDelayed(this, 500)
            }
        }
        poller = r
        handler.postDelayed(r, 500)
    }

    private fun stopPolling() {
        poller?.let { handler.removeCallbacks(it) }
        poller = null
    }

    private fun unregister() {
        receiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        receiver = null
    }

    private fun resolveSuccess(path: String) {
        if (resolved) return
        resolved = true
        pendingResult?.success(path)
        pendingResult = null
    }

    private fun resolveError(code: String, message: String) {
        if (resolved) return
        resolved = true
        pendingResult?.error(code, message, null)
        pendingResult = null
    }

    private fun queryStatus(dm: DownloadManager): Int {
        val q = DownloadManager.Query().setFilterById(downloadId)
        var cur: Cursor? = null
        var status = -1
        try {
            cur = dm.query(q)
            if (cur != null && cur.moveToFirst()) {
                status = cur.getInt(cur.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            }
        } catch (_: Exception) {
        } finally {
            cur?.close()
        }
        return status
    }

    private fun notifyProgress(percent: Int) {
        val p = percent.coerceIn(0, 100)
        handler.post { progressSink?.success(p) }
    }

    override fun onDestroy() {
        stopPolling(); unregister()
        super.onDestroy()
    }
}
