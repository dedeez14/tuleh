import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_config.dart';
import '../network/api_client.dart';
import '../storage/secure_storage.dart';
import 'log_cincin.dart';
import 'pelapor_diagnostik.dart';

/// Konteks perangkat untuk laporan diagnostik (tanpa data pribadi).
class KonteksPerangkat {
  KonteksPerangkat._();

  /// Lokasi layar terakhir (diisi pengamat router).
  static String? layar;
  static String? _perangkat;

  /// Dibaca sekali saat aplikasi mulai (asinkron, tak menahan tampilan pertama).
  static Future<void> muat() async {
    if (!Platform.isAndroid) return;
    try {
      final a = await DeviceInfoPlugin().androidInfo;
      _perangkat = '${a.manufacturer} ${a.model} (Android ${a.version.release}, SDK ${a.version.sdkInt})';
    } catch (_) {}
  }

  static Map<String, dynamic> sekarang() => {
    'layar': layar,
    'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'perangkat': _perangkat,
    'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
  };
}

/// Token untuk header laporan — token Mode Demo tidak dikirim.
Future<String?> Function() tokenDiagnostik(SecureStorage storage) => () async {
  final t = await storage.readToken();
  return t == null || t.isEmpty || t == 'demo-token' ? null : t;
};

/// Pelapor dengan Dio sendiri (tanpa interceptor aplikasi): laporan crash
/// harus tetap bisa terkirim walau graf provider/interceptor yang rusak.
PelaporDiagnostik buatPelaporDiagnostik({required String versi, SecureStorage? storage}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.defaultBaseUrl + AppConfig.apiPrefix,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: const {'Accept': 'application/json'},
      validateStatus: (_) => true,
    ),
  );
  return PelaporDiagnostik(
    dio: dio,
    simpan: PenyimpanDiagnostikBerkas(),
    versi: versi,
    token: tokenDiagnostik(storage ?? SecureStorage(const FlutterSecureStorage())),
    konteksDasar: KonteksPerangkat.sekarang,
  );
}

/// Pelapor aplikasi. `main()` meng-override dengan instans yang sama yang
/// dipasang di penangan galat global; uji meng-override dengan tiruan.
final pelaporDiagnostikProvider = Provider<PelaporDiagnostik>(
  (ref) => buatPelaporDiagnostik(
    versi: ref.watch(appVersionProvider),
    storage: ref.watch(secureStorageProvider),
  ),
);

/// Pasang penangkap galat global: galat framework (`FlutterError.onError`)
/// → jenis `error`; galat asinkron tak tertangani (`PlatformDispatcher`) →
/// `crash`. Zona (`runZonedGuarded` di `main`) memakai [laporkanCrashZona].
void pasangPenangkapGalat(PelaporDiagnostik pelapor) {
  final bawaan = FlutterError.onError;
  FlutterError.onError = (details) {
    if (bawaan != null) {
      bawaan(details);
    } else {
      FlutterError.presentError(details);
    }
    if (details.silent) return; // galat yang sengaja dibungkam framework
    pelapor.laporkanGalat(
      details.exception,
      details.stack,
      jenis: JenisDiagnostik.error,
      konteks: {if (details.library != null) 'pustaka': details.library},
    );
  };
  PlatformDispatcher.instance.onError = (galat, stack) {
    pelapor.laporkanGalat(galat, stack, jenis: JenisDiagnostik.crash);
    return true;
  };

  // Salin keluaran debugPrint ke log cincin (bahan "Kirim laporan ke dukungan").
  final cetakBawaan = debugPrint;
  debugPrint = (String? pesan, {int? wrapWidth}) {
    if (pesan != null) LogCincin.global.catat(pesan, tingkat: 'D');
    cetakBawaan(pesan, wrapWidth: wrapWidth);
  };
}

void laporkanCrashZona(PelaporDiagnostik pelapor, Object galat, StackTrace stack) {
  pelapor.laporkanGalat(galat, stack, jenis: JenisDiagnostik.crash);
}
