import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../constants/app_config.dart';
import '../storage/secure_storage.dart';
import 'antrean.dart';
import 'pengurai.dart';
import 'salinan_db.dart';

/// Sinkronisasi latar belakang (WorkManager): antrean kirim tetap diproses
/// walau aplikasi ditutup — begitu jaringan tersedia (tugas sekali jalan yang
/// didaftarkan tiap ada yang diantrekan) dan berkala tiap 15 menit sebagai
/// jaring pengaman. Isolate latar membuka SQLite yang sama; agar tidak
/// mengirim ganda dengan pengurai di aplikasi, dipakai [KunciPengurai].
class SinkronLatar {
  static const tugasPeriodik = 'tuleh.sinkron.periodik';
  static const tugasSekali = 'tuleh.sinkron.sekali';

  static bool _siap = false;

  /// Dipanggil sekali dari main(): daftarkan dispatcher + tugas berkala.
  static Future<void> siapkan() async {
    if (!Platform.isAndroid) return;
    try {
      await Workmanager().initialize(sinkronLatarDispatcher);
      await Workmanager().registerPeriodicTask(
        tugasPeriodik,
        tugasPeriodik,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      _siap = true;
    } catch (_) {
      // Tanpa WorkManager aplikasi tetap menyinkronkan saat terbuka.
    }
  }

  /// Ada yang baru diantrekan → jalankan begitu jaringan ada (juga saat app
  /// tertutup). Aman dipanggil berulang (tugas lama diganti).
  static Future<void> jadwalkanSekali() async {
    if (!Platform.isAndroid || !_siap) return;
    try {
      await Workmanager().registerOneOffTask(
        tugasSekali,
        tugasSekali,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
      );
    } catch (_) {}
  }
}

/// Titik masuk isolate latar (harus top-level & dipertahankan).
@pragma('vm:entry-point')
void sinkronLatarDispatcher() {
  Workmanager().executeTask((tugas, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      return await jalankanSinkronLatar();
    } catch (_) {
      return true; // jangan diulang WorkManager tanpa henti; tugas berkala tetap ada
    }
  });
}

/// Proses antrean dari isolate latar. Mengembalikan true (selesai) —
/// kegagalan jaringan ditangani mundur oleh pengurai, bukan oleh WorkManager.
Future<bool> jalankanSinkronLatar({SalinanDb? db, Dio? dio, KunciPengurai? kunci, String? token}) async {
  token ??= await SecureStorage(const FlutterSecureStorage()).readToken();
  if (token == null || token.isEmpty) return true;

  final k = kunci ?? KunciPengurai();
  if (await k.terkunci()) return true; // aplikasi sedang menguraikan sendiri

  final basis = db ?? SalinanDb.buka();
  final store = AntreanDriftStore(basis);
  try {
    if ((await store.ringkas()).menunggu == 0) return true;
    final http = dio ??
        Dio(
          BaseOptions(
            baseUrl: AppConfig.defaultBaseUrl + AppConfig.apiPrefix,
            connectTimeout: AppConfig.connectTimeout,
            receiveTimeout: AppConfig.receiveTimeout,
            headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
            validateStatus: (_) => true,
          ),
        );
    final pengurai = PenguraiAntrean(
      store: store,
      dio: http,
      koneksi: null,
      penyiap: {'SESI_BUKA': (b) => isiGudangId(http, b)},
    );
    await k.kunci();
    try {
      await pengurai.jalankan();
    } finally {
      pengurai.hentikan();
      await k.buka();
    }
    return true;
  } finally {
    if (db == null) await basis.close();
  }
}

/// Kunci berkas sederhana antara isolate aplikasi dan isolate latar: yang
/// sedang memegang kunci (< [usiaMaks]) yang mengirim; yang lain mengalah.
class KunciPengurai {
  KunciPengurai({this.dir, this.usiaMaks = const Duration(minutes: 3)});

  final Directory? dir;
  final Duration usiaMaks;

  Future<File> _berkas() async {
    final d = dir ?? await getApplicationSupportDirectory();
    return File('${d.path}/pengurai.lock');
  }

  Future<bool> terkunci() async {
    try {
      final f = await _berkas();
      if (!await f.exists()) return false;
      final isi = await f.readAsString();
      final t = DateTime.tryParse(isi.trim());
      if (t == null) return false;
      return DateTime.now().difference(t) < usiaMaks;
    } catch (_) {
      return false;
    }
  }

  Future<void> kunci() async {
    try {
      final f = await _berkas();
      await f.writeAsString(DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<void> buka() async {
    try {
      final f = await _berkas();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
