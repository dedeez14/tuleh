import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/demo/demo_session.dart';
import '../../features/langganan/domain/langganan.dart';
import '../constants/app_config.dart';
import '../diagnostik/log_cincin.dart';
import '../offline/koneksi.dart';
import '../offline/salinan_db.dart';
import '../offline/salinan_interceptor.dart';
import '../offline/salinan_store.dart';
import '../storage/secure_storage.dart';
import 'api_error_mapper.dart';

/// Versi aplikasi untuk header `X-Tuleh-Version` (Auto-Update).
/// Di-override di `main()` setelah membaca PackageInfo.
final appVersionProvider = Provider<String>((ref) => '0.0.0');

/// Basis data offline (salinan baca + antrean kirim). Satu untuk seluruh
/// aplikasi; test meng-override store-nya, bukan basis datanya.
final salinanDbProvider = Provider<SalinanDb>((ref) {
  final db = SalinanDb.buka();
  ref.onDispose(db.close);
  return db;
});

/// Penyimpanan salinan baca (mode offline). Di perangkat: SQLite; test
/// meng-override dengan [SalinanMemori].
final salinanStoreProvider = Provider<SalinanStore>(
  (ref) => SalinanDriftStore(ref.watch(salinanDbProvider)),
);

/// true saat server membalas HTTP 426 → wajib perbarui aplikasi.
final updateRequiredProvider = StateProvider<bool>((ref) => false);

/// true saat token ditolak (401) → sesi berakhir, arahkan ke login.
/// Dibaca `SesiBerakhirGate` (app.dart) yang membersihkan sesi.
final sessionExpiredProvider = StateProvider<bool>((ref) => false);

/// Dinaikkan setiap endpoint ber-token menjawab 403 (hak akses ditolak).
/// `IdentitasGate` memuat ulang `/auth/me` sekali agar gerbang tombol ikut
/// menyesuaikan; permintaan itu sendiri tetap gagal — server yang berwenang.
final hakDitolakProvider = StateProvider<int>((ref) => 0);

/// Diisi saat endpoint tulis menjawab 402 (langganan perusahaan diblokir):
/// pesan & tautan perpanjang dari server. `LanggananGate` menampilkan layar
/// "Langganan berakhir"; permintaan itu TIDAK diantrekan.
final langgananTerkunciProvider = StateProvider<LanggananTerkunci?>((ref) => null);

/// Jalur yang 401-nya berarti "kredensial salah", bukan "sesi berakhir".
const _jalurTanpaSesi = ['/auth/login'];

/// Dio terkonfigurasi: base URL MOVERA, interceptor header versi/platform +
/// token + toko aktif, deteksi 426/401/402. validateStatus longgar → envelope
/// dinormalisasi di lapisan data (bukan lempar DioException untuk 4xx/5xx);
/// klasifikasi gangguan (408/429/5xx) ada di [SalinanInterceptor], antrean,
/// dan [ApiException.isGangguan].
final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final version = ref.watch(appVersionProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.defaultBaseUrl + AppConfig.apiPrefix,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: const {'Accept': 'application/json'},
      validateStatus: (_) => true,
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.headers[AppConfig.versionHeader] = version;
        options.headers[AppConfig.platformHeader] = AppConfig.platform;
        options.extra['_mulai'] = DateTime.now().millisecondsSinceEpoch;
        final token = await storage.readToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
          final tokoId = await storage.readActiveTokoId();
          if (tokoId != null &&
              tokoId.isNotEmpty &&
              !options.queryParameters.containsKey('toko_id')) {
            options.queryParameters['toko_id'] = tokoId;
          }
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final code = response.statusCode ?? 0;
        final o = response.requestOptions;
        final mulai = o.extra['_mulai'];
        LogCincin.global.catat(
          'HTTP ${o.method} ${o.path} → $code'
          '${mulai is int ? ' (${DateTime.now().millisecondsSinceEpoch - mulai} ms)' : ''}',
        );
        if (code == 426) {
          ref.read(updateRequiredProvider.notifier).state = true;
        } else if (code == 401) {
          // Hanya bila token memang dikirim: 401 dari /auth/login berarti
          // sandi salah, dan permintaan tanpa token bukan "sesi berakhir".
          final bertoken = o.headers['Authorization'] != null;
          if (bertoken && !_jalurTanpaSesi.contains(o.path)) {
            ref.read(sessionExpiredProvider.notifier).state = true;
          }
        } else if (code == 403) {
          // Hak dicabut/ditambah pemilik saat aplikasi terbuka. `/auth/me`
          // dikecualikan supaya 403 di sana tidak memicu /auth/me lagi tanpa
          // ujung; permintaan tanpa token bukan urusan hak akses.
          final bertoken = o.headers['Authorization'] != null;
          if (bertoken && o.path != '/auth/me') {
            ref.read(hakDitolakProvider.notifier).state++;
          }
        } else if (code == 402) {
          ref.read(langgananTerkunciProvider.notifier).state = LanggananTerkunci.dariAmplop(
            response.data,
            pesanBawaan: ApiErrorMapper.statusMessage(402),
          );
        }
        handler.next(response);
      },
      onError: (e, handler) {
        LogCincin.global.catat('HTTP ${e.requestOptions.method} ${e.requestOptions.path} ✕ ${e.type.name}', tingkat: 'W');
        handler.next(e);
      },
    ),
  );

  // Mode Demo dipasang SETELAH interceptor header/toko: `handler.resolve`
  // menghentikan rantai, jadi bila demo di depan, `toko_id` tidak pernah
  // ditambahkan dan semua data demo jatuh ke toko pertama apa pun toko yang
  // dipilih pengguna. Saat demo aktif, permintaan tetap tidak keluar ke jaringan.
  dio.interceptors.add(DemoInterceptor(ref.watch(demoSessionProvider)));

  // Mode offline (fase 1): salinan jawaban GET, disajikan saat jaringan gagal.
  // PALING AKHIR agar kunci memuat toko_id dan jawaban demo tak disalin.
  dio.interceptors.add(
    SalinanInterceptor(
      store: ref.watch(salinanStoreProvider),
      koneksi: ref.read(koneksiProvider.notifier),
    ),
  );

  return dio;
});
