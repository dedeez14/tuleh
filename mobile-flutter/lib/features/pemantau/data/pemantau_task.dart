import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/deteksi_pesanan.dart';

/// Kunci data yang dibagikan aplikasi → isolate layanan
/// (FlutterForegroundTask.saveData/getData, SharedPreferences milik plugin).
///
/// Token ikut disalin ke sini karena isolate layanan tidak memegang
/// SecureStorage aplikasi. Penyimpanan itu privat aplikasi (bukan dapat
/// dibaca aplikasi lain), dan dihapus saat pemantau dimatikan/keluar akun.
abstract final class KunciPemantau {
  static const baseUrl = 'pemantau_base_url';
  static const token = 'pemantau_token';
  static const tokoId = 'pemantau_toko_id';
  static const pantauMeja = 'pemantau_meja';
  static const pantauPesanan = 'pemantau_pesanan';
  static const versi = 'pemantau_versi';
}

/// Pesan isolate layanan → aplikasi (FlutterForegroundTask.sendDataToMain).
abstract final class PesanPemantau {
  static const kejadian = 'kejadian';
  static const sesiBerakhir = 'sesi_berakhir';
  static const status = 'status';
}

/// Saluran notifikasi ALERT (bersuara, heads-up) — terpisah dari notifikasi
/// layanan yang diam (dipasang oleh flutter_foreground_task).
const saluranPesananId = 'pesanan_meja';
const saluranPesananNama = 'Pesanan meja';

@pragma('vm:entry-point')
void mulaiPemantau() {
  FlutterForegroundTask.setTaskHandler(PemantauTask());
}

/// Berjalan di isolate layanan latar depan. Setiap [onRepeatEvent]:
/// tarik /orders dan /bills, bandingkan dengan potret sebelumnya, notifikasi
/// tiap kejadian. Gagal jaringan → diam, coba lagi putaran berikut.
class PemantauTask extends TaskHandler {
  PemantauTask({this.deteksi = const DeteksiPesanan()});

  final DeteksiPesanan deteksi;
  final _notif = FlutterLocalNotificationsPlugin();
  Dio? _dio;
  PotretPesanan? _potret;
  bool _pantauMeja = true;
  bool _pantauPesanan = true;
  bool _sibuk = false;
  int _idNotif = 100;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _notif.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _notif
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            saluranPesananId,
            saluranPesananNama,
            description: 'Pesanan & permintaan bayar dari meja pelanggan',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
    await _muatKonfigurasi();
  }

  Future<void> _muatKonfigurasi() async {
    final baseUrl = await FlutterForegroundTask.getData<String>(
      key: KunciPemantau.baseUrl,
    );
    final token = await FlutterForegroundTask.getData<String>(
      key: KunciPemantau.token,
    );
    final tokoId = await FlutterForegroundTask.getData<String>(
      key: KunciPemantau.tokoId,
    );
    final versi = await FlutterForegroundTask.getData<String>(
      key: KunciPemantau.versi,
    );
    _pantauMeja =
        await FlutterForegroundTask.getData<bool>(
          key: KunciPemantau.pantauMeja,
        ) ??
        true;
    _pantauPesanan =
        await FlutterForegroundTask.getData<bool>(
          key: KunciPemantau.pantauPesanan,
        ) ??
        true;
    if (baseUrl == null || token == null || token.isEmpty) {
      _dio = null;
      return;
    }
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 12),
        validateStatus: (_) => true,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Tuleh-Version': ?versi,
        },
        queryParameters: {
          if (tokoId != null && tokoId.isNotEmpty) 'toko_id': tokoId,
        },
      ),
    );
    _potret = null; // konfigurasi baru → potret ulang tanpa notifikasi
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_sibuk) return;
    _sibuk = true;
    _periksa().whenComplete(() => _sibuk = false);
  }

  Future<void> _periksa() async {
    final dio = _dio;
    if (dio == null) return;

    List<dynamic> orders = const [];
    List<dynamic> tables = const [];
    var adaData = false;

    if (_pantauPesanan) {
      final r = await _ambil(dio, '/orders');
      if (r == null) return; // sesi berakhir → layanan sudah dihentikan
      if (r.$1) {
        adaData = true;
        orders = r.$2 is List ? r.$2 as List : const [];
      }
    }
    if (_pantauMeja) {
      final r = await _ambil(dio, '/bills');
      if (r == null) return;
      if (r.$1) {
        adaData = true;
        final d = r.$2;
        tables = d is Map && d['tables'] is List ? d['tables'] as List : const [];
      }
    }
    if (!adaData) return; // jaringan gagal — jangan rusak potret

    final hasil = deteksi.bandingkan(
      sebelum: _potret,
      orders: orders,
      tables: tables,
    );
    _potret = hasil.potret;

    for (final k in hasil.kejadian) {
      await _tampilkan(k);
    }
    if (hasil.kejadian.isNotEmpty) {
      FlutterForegroundTask.sendDataToMain({
        PesanPemantau.kejadian: [
          for (final k in hasil.kejadian)
            {'judul': k.judul, 'isi': k.isi, 'tujuan': k.tujuan},
        ],
      });
    }
    final ringkas = _ringkasan(hasil.potret);
    FlutterForegroundTask.updateService(
      notificationTitle: 'Tuléh memantau pesanan meja',
      notificationText: ringkas,
    );
  }

  /// (sukses, data) — null bila layanan harus berhenti (token ditolak).
  Future<(bool, dynamic)?> _ambil(Dio dio, String path) async {
    try {
      final res = await dio.get<dynamic>(path);
      final code = res.statusCode ?? 0;
      if (code == 401) {
        FlutterForegroundTask.sendDataToMain({PesanPemantau.sesiBerakhir: true});
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Pemantau pesanan berhenti',
          notificationText: 'Sesi berakhir — buka aplikasi dan masuk lagi.',
        );
        await FlutterForegroundTask.stopService();
        return null;
      }
      final body = res.data;
      if (code < 200 || code >= 300 || body is! Map || body['success'] != true) {
        return (false, null);
      }
      return (true, body['data']);
    } catch (_) {
      return (false, null);
    }
  }

  Future<void> _tampilkan(KejadianPesanan k) async {
    _idNotif = _idNotif >= 1000 ? 100 : _idNotif + 1;
    try {
      await _notif.show(
        id: _idNotif,
        title: k.judul,
        body: k.isi,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            saluranPesananId,
            saluranPesananNama,
            channelDescription: 'Pesanan & permintaan bayar dari meja pelanggan',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            playSound: true,
            enableVibration: true,
            ticker: 'Pesanan baru',
          ),
        ),
        payload: k.tujuan,
      );
    } catch (_) {
      // Notifikasi gagal (izin dicabut) — pesan tetap dikirim ke aplikasi.
    }
  }

  static String _ringkasan(PotretPesanan p) {
    final terisi = p.meja.values.whereType<PotretMeja>().length;
    final mintaBayar = p.meja.values
        .whereType<PotretMeja>()
        .where((m) => m.mintaBayar)
        .length;
    final bagian = <String>[
      if (p.pesanan.isNotEmpty) '${p.pesanan.length} pesanan aktif',
      if (terisi > 0) '$terisi meja terisi',
      if (mintaBayar > 0) '$mintaBayar minta bayar',
    ];
    return bagian.isEmpty ? 'Belum ada pesanan baru' : bagian.join(' · ');
  }

  @override
  void onReceiveData(Object data) {
    // Aplikasi mengirim {'muat_ulang': true} setelah ganti toko/akun.
    if (data is Map && data['muat_ulang'] == true) {
      _muatKonfigurasi();
    }
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp('/');

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
